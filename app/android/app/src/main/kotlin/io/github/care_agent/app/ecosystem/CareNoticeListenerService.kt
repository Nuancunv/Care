package io.github.care_agent.app.ecosystem

import android.app.Notification
import android.content.Context
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Pure privacy filter for optional notification ingestion.
 * Blocks OTP/verification codes and restricts capture strictly to user allow-listed packages.
 */
object NoticePrivacyFilter {
    private val SENSITIVE_PATTERN = Regex(
        """(?i)(验证码|校验码|动态码|取款码|密码|otp|verification\s*code|passcode|cvv|pin\s*code)""",
    )

    fun shouldCapture(packageName: String, title: String, text: String, allowList: Set<String>): Boolean {
        if (allowList.isEmpty() || packageName !in allowList) return false
        val combined = "$title $text"
        if (combined.isBlank()) return false
        if (SENSITIVE_PATTERN.containsMatchIn(combined)) return false
        return true
    }

    fun sanitizeSnippet(raw: String, maxLength: Int = 200): String {
        val compact = raw.replace(Regex("""\s+"""), " ").trim()
        return if (compact.length <= maxLength) compact else compact.substring(0, maxLength) + "…"
    }
}

object CareNoticeInbox {
    private const val PREFS = "care_notice_inbox"
    private const val KEY_ALLOW_LIST = "allow_list"
    private const val MAX_ITEMS = 50

    private val ring = ArrayDeque<Map<String, Any?>>()

    fun getAllowList(context: Context): Set<String> =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getStringSet(KEY_ALLOW_LIST, emptySet())
            ?.toSet() ?: emptySet()

    fun setAllowList(context: Context, packages: List<String>) {
        val cleaned = packages.map { it.trim() }.filter { it.isNotEmpty() }.toSet()
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(KEY_ALLOW_LIST, cleaned)
            .apply()
    }

    fun isEnabledInSystem(context: Context): Boolean {
        val enabled = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: return false
        return enabled.contains(context.packageName)
    }

    fun record(context: Context, packageName: String, title: String, text: String, postedAtMs: Long) {
        val allowList = getAllowList(context)
        if (!NoticePrivacyFilter.shouldCapture(packageName, title, text, allowList)) return
        val item = mapOf(
            "packageName" to packageName,
            "title" to NoticePrivacyFilter.sanitizeSnippet(title, 80),
            "text" to NoticePrivacyFilter.sanitizeSnippet(text, 200),
            "postedAtMs" to postedAtMs,
        )
        synchronized(ring) {
            if (ring.size >= MAX_ITEMS) ring.removeFirst()
            ring.addLast(item)
        }
    }

    fun recent(limit: Int = 20): List<Map<String, Any?>> = synchronized(ring) {
        ring.takeLast(limit.coerceIn(0, MAX_ITEMS)).reversed()
    }

    fun clear() = synchronized(ring) { ring.clear() }
}

/**
 * Optional Android NotificationListenerService (off by default until user enables Notification Access
 * AND adds specific packages like express delivery / flight / calendar apps to the allow-list).
 */
class CareNoticeListenerService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val item = sbn ?: return
        if (item.packageName == packageName) return
        val extras = item.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        CareNoticeInbox.record(applicationContext, item.packageName, title, text, item.postTime)
    }
}
