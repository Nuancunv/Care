package io.github.care_agent.app.proactive

import java.util.Calendar

/**
 * Pure scheduling & quiet-hours policy for Care's low-power background triggers.
 * Supports wrap-around quiet windows (e.g., 23:00 -> 07:30) and computes next fire delays
 * for WorkManager without ever requiring a 24h awake PRoot process (AGENTS.md §3.2).
 */
object QuietHoursPolicy {
    fun parseMinutesOfDay(hhmm: String, fallbackMinutes: Int): Int {
        val parts = hhmm.trim().split(":")
        if (parts.size != 2) return fallbackMinutes
        val h = parts[0].toIntOrNull() ?: return fallbackMinutes
        val m = parts[1].toIntOrNull() ?: return fallbackMinutes
        if (h !in 0..23 || m !in 0..59) return fallbackMinutes
        return h * 60 + m
    }

    fun isQuietMinute(minuteOfDay: Int, startMinute: Int, endMinute: Int): Boolean {
        if (startMinute == endMinute) return false
        return if (startMinute < endMinute) {
            minuteOfDay in startMinute until endMinute
        } else {
            // Wrap-around overnight window (e.g., 23:00 -> 07:30)
            minuteOfDay >= startMinute || minuteOfDay < endMinute
        }
    }

    fun isNowQuiet(nowMs: Long, startHHmm: String, endHHmm: String): Boolean {
        val cal = Calendar.getInstance().apply { timeInMillis = nowMs }
        val minuteOfDay = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        val start = parseMinutesOfDay(startHHmm, 23 * 60)
        val end = parseMinutesOfDay(endHHmm, 7 * 60 + 30)
        return isQuietMinute(minuteOfDay, start, end)
    }

    /**
     * Computes milliseconds from [nowMs] until the next occurrence of [targetHHmm].
     * Always returns >= 60_000 ms (1 minute) to avoid tight re-scheduling loops.
     */
    fun delayUntilNextDailyMs(nowMs: Long, targetHHmm: String): Long {
        val targetMin = parseMinutesOfDay(targetHHmm, 8 * 60 + 30)
        val cal = Calendar.getInstance().apply {
            timeInMillis = nowMs
            set(Calendar.HOUR_OF_DAY, targetMin / 60)
            set(Calendar.MINUTE, targetMin % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (cal.timeInMillis <= nowMs + 60_000L) {
            cal.add(Calendar.DAY_OF_YEAR, 1)
        }
        return (cal.timeInMillis - nowMs).coerceAtLeast(60_000L)
    }
}
