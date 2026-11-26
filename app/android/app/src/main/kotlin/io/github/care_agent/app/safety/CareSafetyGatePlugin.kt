// Care Native SafetyGate (AGENTS.md §1.3 — SafetyGate Supremacy).
package io.github.care_agent.app.safety

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

enum class RiskLevel(val wire: String) {
    L0_READ_ONLY("L0"),
    L1_LOCAL_LOW_RISK("L1"),
    L2_HIGH_RISK("L2"),
}

data class SafetyApprovalRequest(
    val id: String,
    val action: String,
    val summary: String,
    val target: String?,
    val riskLevel: RiskLevel,
    val createdAtMs: Long,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "action" to action,
        "summary" to summary,
        "target" to target,
        "riskLevel" to riskLevel.wire,
        "createdAtMs" to createdAtMs,
    )
}

/**
 * Pure policy classifier: L2 high-risk actions ALWAYS require explicit native human approval.
 * No prompt, config flag, or plugin hook can bypass this gate.
 */
object SafetyGatePolicy {
    private val HIGH_RISK_ACTIONS = setOf(
        "accessibility_write",
        "accessibility_click",
        "accessibility_back",
        "accessibility_home",
        "send_external_message",
        "send_email",
        "delete_file",
        "payment_action",
        "system_settings_write",
        "shell_high_risk",
        "privacy_cross_bot_export",
    )

    private val LOW_RISK_LOCAL_ACTIONS = setOf(
        "calendar_write",
        "alarm_set",
        "reminder_create",
        "memory_write",
    )

    fun classify(action: String): RiskLevel {
        val normalized = action.trim().lowercase()
        return when {
            normalized in HIGH_RISK_ACTIONS -> RiskLevel.L2_HIGH_RISK
            normalized in LOW_RISK_LOCAL_ACTIONS -> RiskLevel.L1_LOCAL_LOW_RISK
            else -> RiskLevel.L2_HIGH_RISK // Fail-closed for unknown privileged actions.
        }
    }

    fun requiresExplicitApproval(action: String): Boolean = classify(action) == RiskLevel.L2_HIGH_RISK
}

/**
 * Process-wide Kotlin coordinator issuing single-use, time-bounded native approval tokens
 * and holding the global emergency-stop kill switch for mid-task user takeover (M3).
 */
object CareSafetyGateCoordinator {
    private const val TOKEN_TTL_MS = 60_000L

    private data class IssuedToken(
        val action: String,
        val expiresAtMs: Long,
    )

    private val tokens = ConcurrentHashMap<String, IssuedToken>()
    private val emergencyStopped = AtomicBoolean(false)

    fun triggerEmergencyStop() {
        emergencyStopped.set(true)
        tokens.clear()
    }

    fun clearEmergencyStop() {
        emergencyStopped.set(false)
    }

    fun isEmergencyStopped(): Boolean = emergencyStopped.get()

    fun issueApprovalToken(action: String, nowMs: Long = System.currentTimeMillis()): String {
        val token = "care-gate-${UUID.randomUUID()}"
        tokens[token] = IssuedToken(action = action.trim().lowercase(), expiresAtMs = nowMs + TOKEN_TTL_MS)
        return token
    }

    /**
     * Atomically consumes a single-use approval token. Rejects missing, replayed, expired,
     * mismatched-action, or emergency-stopped tokens.
     */
    fun consumeApprovalToken(
        token: String?,
        expectedAction: String,
        nowMs: Long = System.currentTimeMillis(),
    ): Boolean {
        if (emergencyStopped.get()) return false
        if (token.isNullOrBlank()) return false
        val record = tokens.remove(token) ?: return false
        if (nowMs > record.expiresAtMs) return false
        return record.action == expectedAction.trim().lowercase()
    }

    internal fun resetForTest() {
        tokens.clear()
        emergencyStopped.set(false)
    }
}

/**
 * Flutter platform bridge for Care's native SafetyGate:
 * - MethodChannel `care/safety`
 * - EventChannel  `care/safety/events`
 */
class CareSafetyGatePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    @Volatile private var eventSink: EventChannel.EventSink? = null
    private val pending = ConcurrentHashMap<String, SafetyApprovalRequest>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods = MethodChannel(binding.binaryMessenger, "care/safety").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "care/safety/events").also { it.setStreamHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPending" -> result.success(pending.values.sortedBy { it.createdAtMs }.map { it.toMap() })
            "evaluateAction" -> {
                val action = call.argument<String>("action") ?: ""
                val summary = call.argument<String>("summary") ?: action
                val target = call.argument<String>("target")
                val level = SafetyGatePolicy.classify(action)
                if (level == RiskLevel.L2_HIGH_RISK) {
                    val req = SafetyApprovalRequest(
                        id = UUID.randomUUID().toString(),
                        action = action,
                        summary = summary,
                        target = target,
                        riskLevel = level,
                        createdAtMs = System.currentTimeMillis(),
                    )
                    pending[req.id] = req
                    emitPending()
                    result.success(mapOf("allowed" to false, "requiresApproval" to true, "request" to req.toMap()))
                } else {
                    result.success(mapOf("allowed" to true, "requiresApproval" to false, "riskLevel" to level.wire))
                }
            }
            "resolve" -> {
                val id = call.argument<String>("id") ?: ""
                val approved = call.argument<Boolean>("approved") == true
                val removed = pending.remove(id)
                val approvalToken = if (removed != null && approved && !CareSafetyGateCoordinator.isEmergencyStopped()) {
                    CareSafetyGateCoordinator.issueApprovalToken(removed.action)
                } else {
                    null
                }
                emitPending()
                result.success(
                    mapOf(
                        "resolved" to (removed != null),
                        "approved" to approved,
                        "approvalToken" to approvalToken,
                    ),
                )
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        eventSink = sink
        emitPending()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emitPending() {
        val snapshot = pending.values.sortedBy { it.createdAtMs }.map { it.toMap() }
        main.post { eventSink?.success(mapOf("type" to "pending", "items" to snapshot)) }
    }
}
