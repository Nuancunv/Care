// Adapted from ccch1mneyyy/dsh-Go (AGPL-3.0); see root THIRD_PARTY_NOTICES.md.
package io.github.care_agent.app.runtime

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import io.github.care_agent.app.MainActivity

/**
 * Lightweight foreground service active ONLY while the local runtime is installing or running.
 * Releases immediately on stop — never holds a 24h idle wake lock (AGENTS.md §3.2).
 */
class CareRuntimeService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_INSTALL -> promote("正在本机解压 Care 离线引擎…")
            ACTION_RUN -> promote("Care 本机助手运行中")
            else -> promote("Care 本机引擎")
        }
        return START_NOT_STICKY
    }

    private fun promote(text: String) {
        ensureChannel()
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Care")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .setContentIntent(pi)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun ensureChannel() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            val ch = NotificationChannel(CHANNEL_ID, "Care 本机引擎", NotificationManager.IMPORTANCE_LOW).apply {
                description = "保持 Care 本机对话引擎在活跃任务期间稳定运行"
                setShowBadge(false)
            }
            nm.createNotificationChannel(ch)
        }
    }

    companion object {
        private const val CHANNEL_ID = "care_runtime"
        private const val NOTIFICATION_ID = 3080
        const val ACTION_INSTALL = "io.github.care_agent.app.ACTION_INSTALL"
        const val ACTION_RUN = "io.github.care_agent.app.ACTION_RUN"
        const val ACTION_STOP = "io.github.care_agent.app.ACTION_STOP"

        fun start(context: Context, action: String) {
            val intent = Intent(context, CareRuntimeService::class.java).setAction(action)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && action != ACTION_STOP) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }
}
