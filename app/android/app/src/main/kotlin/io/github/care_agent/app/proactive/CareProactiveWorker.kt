package io.github.care_agent.app.proactive

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.github.care_agent.app.MainActivity
import java.util.concurrent.TimeUnit

/**
 * Low-power WorkManager worker for morning/evening briefings and periodic life reminders.
 * Runs briefly, respects quiet hours, posts an interactive notification (Done / Snooze 15m),
 * and re-enqueues the next daily/periodic occurrence before exiting cleanly (AGENTS.md §3.2).
 */
class CareProactiveWorker(
    context: Context,
    params: WorkerParameters,
) : Worker(context, params) {

    override fun doWork(): Result {
        val kind = inputData.getString(KEY_KIND) ?: return Result.success()
        val id = inputData.getString(KEY_ID) ?: kind
        val title = inputData.getString(KEY_TITLE) ?: "Care 提醒"
        val body = inputData.getString(KEY_BODY) ?: "打开 Care 查看最新简报与待办"
        val quietStart = inputData.getString(KEY_QUIET_START) ?: "23:00"
        val quietEnd = inputData.getString(KEY_QUIET_END) ?: "07:30"
        val now = System.currentTimeMillis()

        val suppress = kind != KIND_REMINDER_URGENT &&
            QuietHoursPolicy.isNowQuiet(now, quietStart, quietEnd)

        if (!suppress) {
            postNotification(applicationContext, id, kind, title, body)
        }

        // Re-enqueue recurring daily briefings or interval reminders cleanly.
        val dailyTime = inputData.getString(KEY_DAILY_TIME)
        val repeatDays = inputData.getInt(KEY_REPEAT_DAYS, 0)
        if (!dailyTime.isNullOrBlank()) {
            val nextDelay = QuietHoursPolicy.delayUntilNextDailyMs(now, dailyTime)
            enqueue(applicationContext, inputData, nextDelay, uniqueName = "care_briefing_$kind")
        } else if (repeatDays > 0) {
            val nextDelay = TimeUnit.DAYS.toMillis(repeatDays.toLong())
            enqueue(applicationContext, inputData, nextDelay, uniqueName = "care_reminder_$id")
        }

        return Result.success()
    }

    companion object {
        const val CHANNEL_ID = "care_proactive"
        const val KEY_KIND = "kind"
        const val KEY_ID = "id"
        const val KEY_TITLE = "title"
        const val KEY_BODY = "body"
        const val KEY_DAILY_TIME = "dailyTime"
        const val KEY_REPEAT_DAYS = "repeatDays"
        const val KEY_QUIET_START = "quietStart"
        const val KEY_QUIET_END = "quietEnd"

        const val KIND_MORNING = "morning"
        const val KIND_EVENING = "evening"
        const val KIND_REMINDER = "reminder"
        const val KIND_REMINDER_URGENT = "reminder_urgent"

        fun enqueue(context: Context, data: Data, delayMs: Long, uniqueName: String) {
            val req = OneTimeWorkRequestBuilder<CareProactiveWorker>()
                .setInitialDelay(delayMs.coerceAtLeast(1_000L), TimeUnit.MILLISECONDS)
                .setInputData(data)
                .addTag("care_proactive")
                .build()
            WorkManager.getInstance(context)
                .enqueueUniqueWork(uniqueName, ExistingWorkPolicy.REPLACE, req)
        }

        fun postNotification(
            context: Context,
            id: String,
            kind: String,
            title: String,
            body: String,
        ) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID,
                    "Care 简报与提醒",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "早晚简报、日程预警与周期性生活提醒"
                }
                nm.createNotificationChannel(ch)
            }

            val notifId = id.hashCode()
            val openIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("care_notification_id", id)
                putExtra("care_notification_kind", kind)
            }
            val openPi = PendingIntent.getActivity(
                context,
                notifId,
                openIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

            val doneIntent = Intent(context, CareNotificationActionReceiver::class.java).apply {
                action = CareNotificationActionReceiver.ACTION_MARK_DONE
                putExtra(KEY_ID, id)
                putExtra("notifId", notifId)
            }
            val donePi = PendingIntent.getBroadcast(
                context,
                notifId xor 0x101,
                doneIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

            val snoozeIntent = Intent(context, CareNotificationActionReceiver::class.java).apply {
                action = CareNotificationActionReceiver.ACTION_SNOOZE_15M
                putExtra(KEY_ID, id)
                putExtra(KEY_TITLE, title)
                putExtra(KEY_BODY, body)
                putExtra("notifId", notifId)
            }
            val snoozePi = PendingIntent.getBroadcast(
                context,
                notifId xor 0x202,
                snoozeIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

            val notification = Notification.Builder(context, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setSmallIcon(android.R.drawable.ic_popup_reminder)
                .setAutoCancel(true)
                .setContentIntent(openPi)
                .addAction(
                    Notification.Action.Builder(null, "完成", donePi).build(),
                )
                .addAction(
                    Notification.Action.Builder(null, "推迟 15 分钟", snoozePi).build(),
                )
                .build()

            nm.notify(notifId, notification)
        }
    }
}
