import 'dart:async';

import 'package:flutter/services.dart';

/// Platform bridge to Kotlin `CareProactivePlugin` (`care/proactive`, `care/proactive/events`).
abstract class CareProactivePlatform {
  Future<bool> scheduleBriefing({
    required String kind,
    required bool enabled,
    required String time,
    required String quietStart,
    required String quietEnd,
  });

  Future<bool> scheduleReminder({
    required String id,
    required String title,
    required String body,
    required int triggerAtMs,
    required int repeatDays,
    required String quietStart,
    required String quietEnd,
  });

  Future<bool> cancelReminder(String id);
  Future<bool> markReminderDone(String id);
  Future<List<Map<String, Object?>>> listReminders();

  Future<bool> notifyNow({
    required String id,
    required String kind,
    required String title,
    required String body,
  });

  Future<bool> setIdleSleepMinutes(int minutes);
  Stream<Map<String, Object?>> actionEvents();
}

class MethodChannelCareProactivePlatform implements CareProactivePlatform {
  static const _methods = MethodChannel('care/proactive');
  static const _events = EventChannel('care/proactive/events');

  @override
  Future<bool> scheduleBriefing({
    required String kind,
    required bool enabled,
    required String time,
    required String quietStart,
    required String quietEnd,
  }) async =>
      (await _methods.invokeMethod<bool>('scheduleBriefing', {
        'kind': kind,
        'enabled': enabled,
        'time': time,
        'quietStart': quietStart,
        'quietEnd': quietEnd,
      })) ??
      false;

  @override
  Future<bool> scheduleReminder({
    required String id,
    required String title,
    required String body,
    required int triggerAtMs,
    required int repeatDays,
    required String quietStart,
    required String quietEnd,
  }) async =>
      (await _methods.invokeMethod<bool>('scheduleReminder', {
        'id': id,
        'title': title,
        'body': body,
        'triggerAtMs': triggerAtMs,
        'repeatDays': repeatDays,
        'quietStart': quietStart,
        'quietEnd': quietEnd,
      })) ??
      false;

  @override
  Future<bool> cancelReminder(String id) async =>
      (await _methods.invokeMethod<bool>('cancelReminder', {'id': id})) ?? false;

  @override
  Future<bool> markReminderDone(String id) async =>
      (await _methods.invokeMethod<bool>('markReminderDone', {'id': id})) ?? false;

  @override
  Future<List<Map<String, Object?>>> listReminders() async {
    final raw = await _methods.invokeMethod<List<Object?>>('listReminders');
    return _castList(raw);
  }

  @override
  Future<bool> notifyNow({
    required String id,
    required String kind,
    required String title,
    required String body,
  }) async =>
      (await _methods.invokeMethod<bool>('notifyNow', {
        'id': id,
        'kind': kind,
        'title': title,
        'body': body,
      })) ??
      false;

  @override
  Future<bool> setIdleSleepMinutes(int minutes) async =>
      (await _methods.invokeMethod<bool>('setIdleSleepMinutes', {'minutes': minutes})) ??
      false;

  @override
  Stream<Map<String, Object?>> actionEvents() =>
      _events.receiveBroadcastStream().map((e) {
        if (e is Map) return e.map((k, v) => MapEntry(k.toString(), v));
        return const <String, Object?>{};
      });

  List<Map<String, Object?>> _castList(List<Object?>? raw) {
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }
}

/// Platform bridge to Kotlin `CareEcosystemPlugin` (`care/ecosystem`).
abstract class CareEcosystemPlatform {
  Future<Map<String, bool>> calendarPermissionStatus();
  Future<bool> requestCalendarPermission();
  Future<Map<String, Object?>> readCalendarEvents({
    required int startMs,
    required int endMs,
  });
  Future<Map<String, Object?>> createCalendarEvent({
    required String title,
    required int startMs,
    required int endMs,
    String? location,
    String? notes,
  });

  Future<Map<String, Object?>> noticeAccessStatus();
  Future<bool> openNoticeAccessSettings();
  Future<bool> setNoticeAllowList(List<String> packages);
  Future<List<Map<String, Object?>>> getRecentNotices({int limit = 20});
  Future<bool> clearNotices();
}

class MethodChannelCareEcosystemPlatform implements CareEcosystemPlatform {
  static const _methods = MethodChannel('care/ecosystem');

  @override
  Future<Map<String, bool>> calendarPermissionStatus() async {
    final raw = await _methods
        .invokeMethod<Map<Object?, Object?>>('calendarPermissionStatus');
    return {
      'read': raw?['read'] == true,
      'write': raw?['write'] == true,
    };
  }

  @override
  Future<bool> requestCalendarPermission() async =>
      (await _methods.invokeMethod<bool>('requestCalendarPermission')) ?? false;

  @override
  Future<Map<String, Object?>> readCalendarEvents({
    required int startMs,
    required int endMs,
  }) async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      'readCalendarEvents',
      {'startMs': startMs, 'endMs': endMs},
    );
    if (raw == null) return const {'granted': false, 'events': <Object?>[]};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  @override
  Future<Map<String, Object?>> createCalendarEvent({
    required String title,
    required int startMs,
    required int endMs,
    String? location,
    String? notes,
  }) async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      'createCalendarEvent',
      {
        'title': title,
        'startMs': startMs,
        'endMs': endMs,
        'location': location,
        'notes': notes,
      },
    );
    if (raw == null) return const {'created': false};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  @override
  Future<Map<String, Object?>> noticeAccessStatus() async {
    final raw = await _methods
        .invokeMethod<Map<Object?, Object?>>('noticeAccessStatus');
    if (raw == null) return const {'enabled': false, 'allowList': <String>[]};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  @override
  Future<bool> openNoticeAccessSettings() async =>
      (await _methods.invokeMethod<bool>('openNoticeAccessSettings')) ?? false;

  @override
  Future<bool> setNoticeAllowList(List<String> packages) async =>
      (await _methods.invokeMethod<bool>('setNoticeAllowList', {'packages': packages})) ??
      false;

  @override
  Future<List<Map<String, Object?>>> getRecentNotices({int limit = 20}) async {
    final raw = await _methods
        .invokeMethod<List<Object?>>('getRecentNotices', {'limit': limit});
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  @override
  Future<bool> clearNotices() async =>
      (await _methods.invokeMethod<bool>('clearNotices')) ?? false;
}
