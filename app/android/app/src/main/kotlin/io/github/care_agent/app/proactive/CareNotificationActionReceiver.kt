package io.github.care_agent.app.proactive

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.Data
import java.util.concurrent.TimeUnit

/**
 * Handles quick notification actions ("完成" / "推迟 15 分钟") without forcing full UI launch.
 */
class CareNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(CareProactiveWorker.KEY_ID) ?: return
        val notifId = intent.getIntExtra("notifId", id.hashCode())
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(notifId)

        when (intent.action) {
            ACTION_MARK_DONE -> {
                CareProactiveStore.markDone(context, id)
                CareProactivePlugin.emitActionEvent("done", id)
            }
            ACTION_SNOOZE_15M -> {
                val title = intent.getStringExtra(CareProactiveWorker.KEY_TITLE) ?: "Care 提醒"
                val body = intent.getStringExtra(CareProactiveWorker.KEY_BODY) ?: ""
                val data = Data.Builder()
                    .putString(CareProactiveWorker.KEY_KIND, CareProactiveWorker.KIND_REMINDER)
                    .putString(CareProactiveWorker.KEY_ID, id)
                    .putString(CareProactiveWorker.KEY_TITLE, title)
                    .putString(CareProactiveWorker.KEY_BODY, body)
                    .build()
                CareProactiveWorker.enqueue(
                    context = context,
                    data = data,
                    delayMs = TimeUnit.MINUTES.toMillis(15),
                    uniqueName = "care_snooze_$id",
                )
                CareProactivePlugin.emitActionEvent("snoozed", id)
            }
        }
    }

    companion object {
        const val ACTION_MARK_DONE = "io.github.care_agent.app.ACTION_REMINDER_DONE"
        const val ACTION_SNOOZE_15M = "io.github.care_agent.app.ACTION_REMINDER_SNOOZE_15M"
    }
}
