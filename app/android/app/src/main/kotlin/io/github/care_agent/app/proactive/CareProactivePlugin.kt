package io.github.care_agent.app.proactive

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.Data
import androidx.work.WorkManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.care_agent.app.runtime.CareRuntimeController
import org.json.JSONArray
import org.json.JSONObject

internal object CareProactiveStore {
    private const val PREFS = "care_proactive_store"
    private const val KEY_REMINDERS = "reminders_json"

    fun list(context: Context): List<Map<String, Any?>> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_REMINDERS, "[]") ?: "[]"
        val arr = runCatching { JSONArray(raw) }.getOrElse { JSONArray() }
        val out = ArrayList<Map<String, Any?>>(arr.length())
        for (i in 0 until arr.length()) {
            val obj = arr.optJSONObject(i) ?: continue
            out.add(
                mapOf(
                    "id" to obj.optString("id"),
                    "title" to obj.optString("title"),
                    "body" to obj.optString("body"),
                    "triggerAtMs" to obj.optLong("triggerAtMs"),
                    "repeatDays" to obj.optInt("repeatDays", 0),
                    "done" to obj.optBoolean("done", false),
                ),
            )
        }
        return out
    }

    fun upsert(context: Context, item: Map<String, Any?>) {
        val id = item["id"]?.toString() ?: return
        val current = list(context).filterNot { it["id"] == id }.toMutableList()
        current.add(item)
        saveAll(context, current)
    }

    fun remove(context: Context, id: String) {
        saveAll(context, list(context).filterNot { it["id"] == id })
    }

    fun markDone(context: Context, id: String) {
        val updated = list(context).map { item ->
            if (item["id"] == id) item + ("done" to true) else item
        }
        saveAll(context, updated)
    }

    private fun saveAll(context: Context, items: List<Map<String, Any?>>) {
        val arr = JSONArray()
        for (item in items) {
            arr.put(
                JSONObject().apply {
                    put("id", item["id"]?.toString() ?: "")
                    put("title", item["title"]?.toString() ?: "")
                    put("body", item["body"]?.toString() ?: "")
                    put("triggerAtMs", (item["triggerAtMs"] as? Number)?.toLong() ?: 0L)
                    put("repeatDays", (item["repeatDays"] as? Number)?.toInt() ?: 0)
                    put("done", item["done"] == true)
                },
            )
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_REMINDERS, arr.toString())
            .apply()
    }
}

/**
 * Flutter platform bridge for Care's low-power proactive scheduler:
 * - MethodChannel `care/proactive`
 * - EventChannel  `care/proactive/events`
 */
class CareProactivePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var appContext: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "care/proactive").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "care/proactive/events").also { it.setStreamHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        activeSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scheduleBriefing" -> {
                val kind = call.argument<String>("kind") ?: CareProactiveWorker.KIND_MORNING
                val enabled = call.argument<Boolean>("enabled") == true
                val time = call.argument<String>("time") ?: if (kind == CareProactiveWorker.KIND_EVENING) "21:30" else "08:30"
                val quietStart = call.argument<String>("quietStart") ?: "23:00"
                val quietEnd = call.argument<String>("quietEnd") ?: "07:30"
                val uniqueName = "care_briefing_$kind"
                if (!enabled) {
                    WorkManager.getInstance(appContext).cancelUniqueWork(uniqueName)
                } else {
                    val title = if (kind == CareProactiveWorker.KIND_EVENING) "Care 晚间回顾" else "Care 早间简报"
                    val body = if (kind == CareProactiveWorker.KIND_EVENING) {
                        "点击查看今日已完成事项与明日重要安排"
                    } else {
                        "点击查看今日日程、关键待办与周期提醒"
                    }
                    val data = Data.Builder()
                        .putString(CareProactiveWorker.KEY_KIND, kind)
                        .putString(CareProactiveWorker.KEY_ID, uniqueName)
                        .putString(CareProactiveWorker.KEY_TITLE, title)
                        .putString(CareProactiveWorker.KEY_BODY, body)
                        .putString(CareProactiveWorker.KEY_DAILY_TIME, time)
                        .putString(CareProactiveWorker.KEY_QUIET_START, quietStart)
                        .putString(CareProactiveWorker.KEY_QUIET_END, quietEnd)
                        .build()
                    val delay = QuietHoursPolicy.delayUntilNextDailyMs(System.currentTimeMillis(), time)
                    CareProactiveWorker.enqueue(appContext, data, delay, uniqueName)
                }
                result.success(true)
            }
            "scheduleReminder" -> {
                val id = call.argument<String>("id") ?: return result.error("invalid_arg", "missing id", null)
                val title = call.argument<String>("title") ?: "Care 提醒"
                val body = call.argument<String>("body") ?: ""
                val triggerAtMs = (call.argument<Number>("triggerAtMs"))?.toLong()
                    ?: (System.currentTimeMillis() + 60_000L)
                val repeatDays = (call.argument<Number>("repeatDays"))?.toInt() ?: 0
                val quietStart = call.argument<String>("quietStart") ?: "23:00"
                val quietEnd = call.argument<String>("quietEnd") ?: "07:30"

                CareProactiveStore.upsert(
                    appContext,
                    mapOf(
                        "id" to id,
                        "title" to title,
                        "body" to body,
                        "triggerAtMs" to triggerAtMs,
                        "repeatDays" to repeatDays,
                        "done" to false,
                    ),
                )
                val delay = (triggerAtMs - System.currentTimeMillis()).coerceAtLeast(1_000L)
                val data = Data.Builder()
                    .putString(CareProactiveWorker.KEY_KIND, CareProactiveWorker.KIND_REMINDER)
                    .putString(CareProactiveWorker.KEY_ID, id)
                    .putString(CareProactiveWorker.KEY_TITLE, title)
                    .putString(CareProactiveWorker.KEY_BODY, body)
                    .putInt(CareProactiveWorker.KEY_REPEAT_DAYS, repeatDays)
                    .putString(CareProactiveWorker.KEY_QUIET_START, quietStart)
                    .putString(CareProactiveWorker.KEY_QUIET_END, quietEnd)
                    .build()
                CareProactiveWorker.enqueue(appContext, data, delay, "care_reminder_$id")
                result.success(true)
            }
            "cancelReminder" -> {
                val id = call.argument<String>("id") ?: ""
                WorkManager.getInstance(appContext).cancelUniqueWork("care_reminder_$id")
                WorkManager.getInstance(appContext).cancelUniqueWork("care_snooze_$id")
                CareProactiveStore.remove(appContext, id)
                result.success(true)
            }
            "markReminderDone" -> {
                val id = call.argument<String>("id") ?: ""
                CareProactiveStore.markDone(appContext, id)
                result.success(true)
            }
            "listReminders" -> result.success(CareProactiveStore.list(appContext))
            "notifyNow" -> {
                val id = call.argument<String>("id") ?: "care_now"
                val kind = call.argument<String>("kind") ?: CareProactiveWorker.KIND_MORNING
                val title = call.argument<String>("title") ?: "Care 简报"
                val body = call.argument<String>("body") ?: ""
                CareProactiveWorker.postNotification(appContext, id, kind, title, body)
                result.success(true)
            }
            "setIdleSleepMinutes" -> {
                val minutes = (call.argument<Number>("minutes"))?.toInt() ?: 15
                CareRuntimeController.get(appContext).setIdleSleepMinutes(minutes)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        activeSink = events
    }

    override fun onCancel(arguments: Any?) {
        activeSink = null
    }

    companion object {
        private val main = Handler(Looper.getMainLooper())
        @Volatile private var activeSink: EventChannel.EventSink? = null

        fun emitActionEvent(action: String, id: String) {
            main.post {
                activeSink?.success(mapOf("type" to "notification_action", "action" to action, "id" to id))
            }
        }
    }
}
