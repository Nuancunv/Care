package io.github.care_agent.app.runtime

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter platform bridge for Care's local runtime:
 * - MethodChannel `care/runtime`
 * - EventChannel  `care/runtime/events`
 */
class CareRuntimePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var appContext: Context
    private lateinit var controller: CareRuntimeController
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var sink: CareRuntimeController.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        controller = CareRuntimeController.get(appContext)
        methods = MethodChannel(binding.binaryMessenger, "care/runtime").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "care/runtime/events").also { it.setStreamHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink?.let { controller.removeSink(it) }
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(controller.status())
            "install" -> controller.install { error ->
                if (error == null) result.success(null)
                else result.error("install_failed", error.message, null)
            }
            "start" -> {
                val rawEnv = call.argument<Map<String, Any?>>("env") ?: emptyMap()
                val env = rawEnv.mapNotNull { (k, v) -> v?.toString()?.let { k to it } }.toMap()
                controller.start(env)
                result.success(null)
            }
            "stop" -> {
                controller.stop()
                result.success(null)
            }
            "getLogs" -> result.success(controller.recentLogs(call.argument<Int>("lines") ?: 200))
            "batteryExempt" -> {
                val pm = appContext.getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(pm.isIgnoringBatteryOptimizations(appContext.packageName))
            }
            "requestBatteryExempt" -> {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:${appContext.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                result.success(runCatching { appContext.startActivity(intent) }.isSuccess)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        val listener = CareRuntimeController.EventSink { event -> eventSink.success(event) }
        sink = listener
        controller.addSink(listener)
        eventSink.success(mapOf("type" to "status", "status" to controller.status()))
    }

    override fun onCancel(arguments: Any?) {
        sink?.let { controller.removeSink(it) }
        sink = null
    }
}
