package io.github.care_agent.app.ecosystem

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Flutter platform bridge for on-demand Android ecosystem capabilities (`care/ecosystem`):
 * - System Calendar (READ_CALENDAR / WRITE_CALENDAR, requested only when user opts in)
 * - Optional Notification Inbox (allow-listed packages only, OTP-filtered)
 */
class CareEcosystemPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var appContext: Context
    private lateinit var methods: MethodChannel
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "care/ecosystem").also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQ_CALENDAR) return false
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pendingPermResult?.success(granted)
        pendingPermResult = null
        return true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "calendarPermissionStatus" -> result.success(
                mapOf(
                    "read" to CareCalendarBridge.hasReadPermission(appContext),
                    "write" to CareCalendarBridge.hasWritePermission(appContext),
                ),
            )
            "requestCalendarPermission" -> {
                if (CareCalendarBridge.hasReadPermission(appContext) && CareCalendarBridge.hasWritePermission(appContext)) {
                    return result.success(true)
                }
                val activity: Activity? = activityBinding?.activity
                if (activity == null) return result.success(false)
                pendingPermResult = result
                activity.requestPermissions(
                    arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
                    REQ_CALENDAR,
                )
            }
            "readCalendarEvents" -> {
                val now = System.currentTimeMillis()
                val startMs = (call.argument<Number>("startMs"))?.toLong() ?: now
                val endMs = (call.argument<Number>("endMs"))?.toLong() ?: (now + 7L * 24 * 3600_000L)
                val events = CareCalendarBridge.readEvents(appContext, startMs, endMs)
                result.success(
                    mapOf(
                        "granted" to CareCalendarBridge.hasReadPermission(appContext),
                        "events" to events,
                    ),
                )
            }
            "createCalendarEvent" -> {
                val title = call.argument<String>("title") ?: ""
                val startMs = (call.argument<Number>("startMs"))?.toLong() ?: 0L
                val endMs = (call.argument<Number>("endMs"))?.toLong() ?: (startMs + 30 * 60_000L)
                val location = call.argument<String>("location")
                val notes = call.argument<String>("notes")
                if (title.isBlank() || startMs <= 0L) {
                    return result.error("invalid_arg", "title and startMs required", null)
                }
                val id = CareCalendarBridge.createEvent(appContext, title, startMs, endMs, location, notes)
                result.success(mapOf("created" to (id != null), "id" to id))
            }
            "noticeAccessStatus" -> result.success(
                mapOf(
                    "enabled" to CareNoticeInbox.isEnabledInSystem(appContext),
                    "allowList" to CareNoticeInbox.getAllowList(appContext).sorted(),
                ),
            )
            "openNoticeAccessSettings" -> {
                val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                result.success(runCatching { appContext.startActivity(intent) }.isSuccess)
            }
            "setNoticeAllowList" -> {
                val list = call.argument<List<String>>("packages") ?: emptyList()
                CareNoticeInbox.setAllowList(appContext, list)
                result.success(true)
            }
            "getRecentNotices" -> {
                val limit = (call.argument<Number>("limit"))?.toInt() ?: 20
                result.success(CareNoticeInbox.recent(limit))
            }
            "clearNotices" -> {
                CareNoticeInbox.clear()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        private const val REQ_CALENDAR = 4201
    }
}
