package io.github.care_agent.app.automation

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.care_agent.app.safety.CareSafetyGateCoordinator

/**
 * Flutter platform bridge for Care M3 phone automation (`care/automation`, `care/automation/events`).
 * All mutating actions remain strictly gated by [ProtectedAppsPolicy] + [CareSafetyGateCoordinator].
 */
class CareAutomationPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var appContext: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "care/automation").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "care/automation/events").also { it.setStreamHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        eventSink = null
    }

    private fun selfCheckMap(): Map<String, Any?> = mapOf(
        "accessibilityEnabled" to ShizukuChannelStatus.isAccessibilityEnabledInSystem(appContext),
        "accessibilityConnected" to CareA11yService.isConnected(),
        "shizukuInstalled" to ShizukuChannelStatus.isShizukuInstalled(appContext),
        "emergencyStopped" to CareSafetyGateCoordinator.isEmergencyStopped(),
        "manufacturer" to Build.MANUFACTURER,
        "brand" to Build.BRAND,
    )

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "selfCheck" -> result.success(selfCheckMap())
            "openAccessibilitySettings" -> {
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                result.success(runCatching { appContext.startActivity(intent) }.isSuccess)
            }
            "captureScreenSummary" -> {
                val service = CareA11yService.activeInstance
                if (service == null) {
                    result.success(
                        mapOf(
                            "available" to false,
                            "reason" to "Accessibility service is not connected.",
                            "nodes" to emptyList<Any>(),
                        ),
                    )
                } else {
                    val maxNodes = (call.argument<Number>("maxNodes"))?.toInt() ?: 60
                    result.success(service.captureSanitizedTree(maxNodes))
                }
            }
            "executeStep" -> {
                val action = call.argument<String>("action") ?: ""
                val approvalToken = call.argument<String>("approvalToken")
                val nodeText = call.argument<String>("nodeText")
                val x = (call.argument<Number>("x"))?.toFloat()
                val y = (call.argument<Number>("y"))?.toFloat()
                val inputText = call.argument<String>("text")

                val service = CareA11yService.activeInstance
                if (service == null) {
                    result.success(
                        mapOf(
                            "ok" to false,
                            "reason" to "Accessibility service is not connected.",
                        ),
                    )
                } else {
                    val outcome = service.executeGatedAction(
                        action = action,
                        approvalToken = approvalToken,
                        nodeText = nodeText,
                        x = x,
                        y = y,
                        inputText = inputText,
                    )
                    emitStatus(selfCheckMap())
                    result.success(outcome)
                }
            }
            "emergencyStop" -> {
                CareSafetyGateCoordinator.triggerEmergencyStop()
                emitStatus(selfCheckMap())
                result.success(true)
            }
            "clearEmergencyStop" -> {
                CareSafetyGateCoordinator.clearEmergencyStop()
                emitStatus(selfCheckMap())
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        eventSink = sink
        emitStatus(selfCheckMap())
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    companion object {
        private val main = Handler(Looper.getMainLooper())
        @Volatile private var eventSink: EventChannel.EventSink? = null

        fun emitStatus(snapshot: Map<String, Any?>) {
            main.post { eventSink?.success(mapOf("type" to "selfCheck", "data" to snapshot)) }
        }
    }
}
