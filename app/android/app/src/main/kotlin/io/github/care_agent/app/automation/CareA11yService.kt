// Adapted in concept from ccch1mneyyy/dsh-Go (AGPL-3.0); see root THIRD_PARTY_NOTICES.md.
package io.github.care_agent.app.automation

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.github.care_agent.app.safety.CareSafetyGateCoordinator

/**
 * Opt-in Android AccessibilityService for Care M3 phone automation.
 *
 * Security invariants (AGENTS.md §1.3):
 * 1. Password fields (`isPassword == true`) are ALWAYS masked on read and refused on write.
 * 2. Hard-protected system/payment/security apps are ALWAYS refused (`ProtectedAppsPolicy`).
 * 3. Every mutating action requires a valid, single-use native SafetyGate approval token
 *    from [CareSafetyGateCoordinator] AND checks the emergency-stop kill switch.
 */
class CareA11yService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        activeInstance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Passive observer only — never acts autonomously on background events.
    }

    override fun onInterrupt() {
        // Trigger safety stop if OS interrupts accessibility binding.
        CareSafetyGateCoordinator.triggerEmergencyStop()
    }

    override fun onDestroy() {
        if (activeInstance === this) activeInstance = null
        super.onDestroy()
    }

    fun captureSanitizedTree(maxNodes: Int = 60): Map<String, Any?> {
        val root = rootInActiveWindow ?: return mapOf(
            "available" to false,
            "reason" to "No active window accessible.",
            "nodes" to emptyList<Any>(),
        )
        val pkg = root.packageName?.toString()
        if (ProtectedAppsPolicy.isHardProtectedPackage(pkg)) {
            return mapOf(
                "available" to false,
                "blocked" to true,
                "packageName" to pkg,
                "reason" to "Screen capture blocked on protected system/security/payment app.",
                "nodes" to emptyList<Any>(),
            )
        }

        val nodes = ArrayList<Map<String, Any?>>()
        collectNodes(root, nodes, maxNodes.coerceIn(1, 120))
        return mapOf(
            "available" to true,
            "blocked" to false,
            "packageName" to (pkg ?: ""),
            "nodes" to nodes,
        )
    }

    private fun collectNodes(node: AccessibilityNodeInfo, out: MutableList<Map<String, Any?>>, limit: Int) {
        if (out.size >= limit) return
        val isPwd = node.isPassword
        val text = if (isPwd) "[REDACTED_PASSWORD]" else (node.text?.toString()?.take(120) ?: "")
        val desc = if (isPwd) "" else (node.contentDescription?.toString()?.take(120) ?: "")
        val interesting = node.isClickable || node.isEditable || text.isNotBlank() || desc.isNotBlank()
        if (interesting) {
            val rect = Rect()
            node.getBoundsInScreen(rect)
            out.add(
                mapOf(
                    "text" to text,
                    "desc" to desc,
                    "clickable" to node.isClickable,
                    "editable" to (node.isEditable && !isPwd),
                    "sensitive" to (isPwd || ProtectedAppsPolicy.containsSensitiveActionText("$text $desc")),
                    "bounds" to listOf(rect.left, rect.top, rect.right, rect.bottom),
                ),
            )
        }
        for (i in 0 until node.childCount) {
            if (out.size >= limit) break
            val child = node.getChild(i) ?: continue
            collectNodes(child, out, limit)
        }
    }

    fun executeGatedAction(
        action: String,
        approvalToken: String?,
        nodeText: String? = null,
        x: Float? = null,
        y: Float? = null,
        inputText: String? = null,
    ): Map<String, Any?> {
        if (CareSafetyGateCoordinator.isEmergencyStopped()) {
            return mapOf("ok" to false, "reason" to "Emergency stop is active; user takeover in effect.")
        }

        val root = rootInActiveWindow
        val pkg = root?.packageName?.toString()
        val hardBlock = ProtectedAppsPolicy.hardRefusalReason(pkg, targetIsPassword = false)
        if (hardBlock != null) {
            return mapOf("ok" to false, "blocked" to true, "reason" to hardBlock)
        }

        // Enforce single-use native SafetyGate approval token for every write/gesture action.
        if (!CareSafetyGateCoordinator.consumeApprovalToken(approvalToken, action)) {
            return mapOf(
                "ok" to false,
                "blocked" to true,
                "reason" to "Missing or invalid native SafetyGate approval token for '$action'.",
            )
        }

        return when (action.lowercase()) {
            "accessibility_click" -> {
                if (!nodeText.isNullOrBlank() && root != null) {
                    val found = root.findAccessibilityNodeInfosByText(nodeText)
                    val target = found.firstOrNull { !it.isPassword && (it.isClickable || it.parent?.isClickable == true) }
                    if (target == null) {
                        mapOf("ok" to false, "reason" to "Target node '$nodeText' not found or blocked.")
                    } else {
                        val clickable = if (target.isClickable) target else target.parent
                        val clicked = clickable?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true
                        mapOf("ok" to clicked, "action" to action, "packageName" to (pkg ?: ""))
                    }
                } else if (x != null && y != null) {
                    val tapped = dispatchTap(x, y)
                    mapOf("ok" to tapped, "action" to action, "packageName" to (pkg ?: ""))
                } else {
                    mapOf("ok" to false, "reason" to "Either nodeText or (x, y) coordinates are required.")
                }
            }
            "accessibility_write" -> {
                if (root == null || inputText == null) {
                    mapOf("ok" to false, "reason" to "Active window and text are required.")
                } else {
                    val target = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
                    if (target == null) {
                        mapOf("ok" to false, "reason" to "No focused input field found.")
                    } else if (target.isPassword) {
                        mapOf("ok" to false, "blocked" to true, "reason" to ProtectedAppsPolicy.hardRefusalReason(pkg, true))
                    } else {
                        val args = Bundle().apply {
                            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, inputText)
                        }
                        val done = target.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                        mapOf("ok" to done, "action" to action, "packageName" to (pkg ?: ""))
                    }
                }
            }
            "accessibility_back" -> mapOf("ok" to performGlobalAction(GLOBAL_ACTION_BACK), "action" to action)
            "accessibility_home" -> mapOf("ok" to performGlobalAction(GLOBAL_ACTION_HOME), "action" to action)
            else -> mapOf("ok" to false, "reason" to "Unsupported automation action: $action")
        }
    }

    private fun dispatchTap(x: Float, y: Float): Boolean {
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0L, 60L)
        return dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    companion object {
        @Volatile var activeInstance: CareA11yService? = null
            private set

        fun isConnected(): Boolean = activeInstance != null
    }
}
