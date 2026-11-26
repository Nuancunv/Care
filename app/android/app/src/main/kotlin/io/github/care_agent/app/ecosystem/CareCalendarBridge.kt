package io.github.care_agent.app.ecosystem

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CalendarContract
import java.util.TimeZone

/**
 * On-demand Android CalendarContract reader & writer (AGENTS.md §3.2 — minimal permissions).
 * Never throws or crashes when calendar permission is denied; returns empty lists gracefully.
 */
object CareCalendarBridge {
    fun hasReadPermission(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED

    fun hasWritePermission(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED

    fun readEvents(context: Context, startMs: Long, endMs: Long, limit: Int = 50): List<Map<String, Any?>> {
        if (!hasReadPermission(context)) return emptyList()
        val builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, startMs)
        ContentUris.appendId(builder, endMs)

        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.ALL_DAY,
        )
        val results = ArrayList<Map<String, Any?>>()
        runCatching {
            context.contentResolver.query(
                builder.build(),
                projection,
                null,
                null,
                "${CalendarContract.Instances.BEGIN} ASC",
            )?.use { cursor ->
                while (cursor.moveToNext() && results.size < limit) {
                    results.add(
                        mapOf(
                            "id" to cursor.getLong(0).toString(),
                            "title" to (cursor.getString(1) ?: "(无标题)"),
                            "startMs" to cursor.getLong(2),
                            "endMs" to cursor.getLong(3),
                            "location" to (cursor.getString(4) ?: ""),
                            "allDay" to (cursor.getInt(5) == 1),
                        ),
                    )
                }
            }
        }
        return results
    }

    fun createEvent(
        context: Context,
        title: String,
        startMs: Long,
        endMs: Long,
        location: String?,
        notes: String?,
    ): String? {
        if (!hasWritePermission(context)) return null
        val calendarId = findPrimaryCalendarId(context) ?: return null
        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DTSTART, startMs)
            put(CalendarContract.Events.DTEND, endMs.coerceAtLeast(startMs + 30 * 60_000L))
            put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            if (!location.isNullOrBlank()) put(CalendarContract.Events.EVENT_LOCATION, location)
            if (!notes.isNullOrBlank()) put(CalendarContract.Events.DESCRIPTION, notes)
        }
        return runCatching {
            context.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)?.lastPathSegment
        }.getOrNull()
    }

    private fun findPrimaryCalendarId(context: Context): Long? {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.IS_PRIMARY,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
        )
        var fallback: Long? = null
        runCatching {
            context.contentResolver.query(
                CalendarContract.Calendars.CONTENT_URI,
                projection,
                "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL} >= ?",
                arrayOf(CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString()),
                null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(0)
                    val isPrimary = cursor.getInt(1) == 1
                    if (isPrimary) return id
                    if (fallback == null) fallback = id
                }
            }
        }
        return fallback
    }
}
