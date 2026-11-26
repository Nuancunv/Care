import 'dart:async';

import 'package:care_app/services/care_m2_bridge.dart';
import 'package:care_app/services/care_storage.dart';
import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemSecrets implements CareSecretStore {
  final Map<String, String> map = {};
  @override
  Future<void> delete(String key) async => map.remove(key);
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
}

class _MemPrefs implements CarePrefsStore {
  final Map<String, String> map = {};
  @override
  Future<String?> getString(String key) async => map[key];
  @override
  Future<void> remove(String key) async => map.remove(key);
  @override
  Future<void> setString(String key, String value) async => map[key] = value;
}

class _MemDocs implements CareDocumentStore {
  final Map<String, String> map = {};
  @override
  Future<String?> readDocument(String filename) async => map[filename];
  @override
  Future<void> writeDocument(String filename, String content) async =>
      map[filename] = content;
}

class _FakeProactivePlatform implements CareProactivePlatform {
  final _events = StreamController<Map<String, Object?>>.broadcast();
  final List<Map<String, Object?>> reminders = [];
  final Map<String, Map<String, Object?>> briefings = {};
  int? lastIdleSleepMinutes;
  String? lastNotifiedTitle;

  @override
  Stream<Map<String, Object?>> actionEvents() => _events.stream;

  @override
  Future<bool> cancelReminder(String id) async {
    reminders.removeWhere((r) => r['id'] == id);
    return true;
  }

  @override
  Future<List<Map<String, Object?>>> listReminders() async =>
      List.of(reminders);

  @override
  Future<bool> markReminderDone(String id) async {
    for (var i = 0; i < reminders.length; i++) {
      if (reminders[i]['id'] == id) {
        reminders[i] = {...reminders[i], 'done': true};
      }
    }
    return true;
  }

  @override
  Future<bool> notifyNow({
    required String id,
    required String kind,
    required String title,
    required String body,
  }) async {
    lastNotifiedTitle = title;
    return true;
  }

  @override
  Future<bool> scheduleBriefing({
    required String kind,
    required bool enabled,
    required String time,
    required String quietStart,
    required String quietEnd,
  }) async {
    briefings[kind] = {
      'enabled': enabled,
      'time': time,
      'quietStart': quietStart,
      'quietEnd': quietEnd,
    };
    return true;
  }

  @override
  Future<bool> scheduleReminder({
    required String id,
    required String title,
    required String body,
    required int triggerAtMs,
    required int repeatDays,
    required String quietStart,
    required String quietEnd,
  }) async {
    reminders.add({
      'id': id,
      'title': title,
      'body': body,
      'triggerAtMs': triggerAtMs,
      'repeatDays': repeatDays,
      'done': false,
    });
    return true;
  }

  @override
  Future<bool> setIdleSleepMinutes(int minutes) async {
    lastIdleSleepMinutes = minutes;
    return true;
  }

  void dispose() => _events.close();
}

class _FakeEcosystemPlatform implements CareEcosystemPlatform {
  bool calendarGranted = false;
  final List<Map<String, Object?>> events = [];
  bool noticeEnabled = true;
  List<String> allowList = ['com.express.app'];
  final List<Map<String, Object?>> notices = [
    {
      'packageName': 'com.express.app',
      'title': '快递到达',
      'text': '您的快递已放入小区丰巢柜',
      'postedAtMs': 1700000000000,
    },
  ];

  @override
  Future<Map<String, bool>> calendarPermissionStatus() async =>
      {'read': calendarGranted, 'write': calendarGranted};

  @override
  Future<bool> clearNotices() async {
    notices.clear();
    return true;
  }

  @override
  Future<Map<String, Object?>> createCalendarEvent({
    required String title,
    required int startMs,
    required int endMs,
    String? location,
    String? notes,
  }) async {
    if (!calendarGranted) return {'created': false};
    events.add({
      'id': 'ev-${events.length + 1}',
      'title': title,
      'startMs': startMs,
      'endMs': endMs,
      'location': location ?? '',
      'allDay': false,
    });
    return {'created': true, 'id': 'ev-${events.length}'};
  }

  @override
  Future<List<Map<String, Object?>>> getRecentNotices({int limit = 20}) async =>
      List.of(notices);

  @override
  Future<Map<String, Object?>> noticeAccessStatus() async =>
      {'enabled': noticeEnabled, 'allowList': allowList};

  @override
  Future<bool> openNoticeAccessSettings() async => true;

  @override
  Future<Map<String, Object?>> readCalendarEvents({
    required int startMs,
    required int endMs,
  }) async =>
      {'granted': calendarGranted, 'events': calendarGranted ? events : []};

  @override
  Future<bool> requestCalendarPermission() async {
    calendarGranted = true;
    return true;
  }

  @override
  Future<bool> setNoticeAllowList(List<String> packages) async {
    allowList = List.of(packages);
    return true;
  }
}

void main() {
  test('CareScheduleController schedules briefings, periodic reminders, and generates local briefings', () async {
    final prefs = _MemPrefs();
    final docs = _MemDocs();
    final proactive = _FakeProactivePlatform();
    final eco = _FakeEcosystemPlatform()
      ..calendarGranted = true
      ..events.add({
        'id': 'ev-1',
        'title': '项目评审会',
        'startMs': DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch,
        'endMs': DateTime.now().add(const Duration(hours: 3)).millisecondsSinceEpoch,
        'location': '会议室 A',
        'allDay': false,
      });

    final container = ProviderContainer(
      overrides: [
        carePrefsStoreProvider.overrideWithValue(prefs),
        careDocumentStoreProvider.overrideWithValue(docs),
        careProactivePlatformProvider.overrideWithValue(proactive),
        careEcosystemPlatformProvider.overrideWithValue(eco),
      ],
    );
    addTearDown(() {
      container.dispose();
      proactive.dispose();
    });

    final ctrl = container.read(careScheduleProvider.notifier);
    await ctrl.updateConfig(
      const CareBriefingConfig(
        morningTime: '08:00',
        eveningTime: '22:00',
        quietStart: '23:30',
        quietEnd: '07:00',
        idleSleepMinutes: 10,
      ),
    );
    expect(proactive.briefings['morning']?['time'], '08:00');
    expect(proactive.briefings['evening']?['time'], '22:00');
    expect(proactive.lastIdleSleepMinutes, 10);

    final rem = await ctrl.addReminder(
      title: '猫粮补货提醒',
      body: '大概还剩 3 天用量',
      triggerAt: DateTime.now().add(const Duration(days: 14)),
      repeatDays: 14,
    );
    expect(container.read(careScheduleProvider).requireValue.activeReminders.length, 1);

    final briefing = await ctrl.generateBriefingNow(CareBriefingKind.morning);
    expect(briefing.summaryMarkdown, contains('项目评审会'));
    expect(briefing.summaryMarkdown, contains('猫粮补货提醒'));
    expect(briefing.summaryMarkdown, contains('快递到达'));
    expect(proactive.lastNotifiedTitle, 'Care 早间简报');

    await ctrl.markReminderDone(rem.id);
    expect(container.read(careScheduleProvider).requireValue.activeReminders, isEmpty);
  });

  test('CareEcosystemController degrades gracefully when calendar permission is denied and works once granted', () async {
    final eco = _FakeEcosystemPlatform();
    final container = ProviderContainer(
      overrides: [careEcosystemPlatformProvider.overrideWithValue(eco)],
    );
    addTearDown(container.dispose);

    final initial = await container.read(careEcosystemProvider.future);
    expect(initial.calendarReadGranted, isFalse);
    expect(initial.upcomingEvents, isEmpty);
    expect(initial.recentNotices.length, 1);

    final ctrl = container.read(careEcosystemProvider.notifier);
    final granted = await ctrl.requestCalendarPermission();
    expect(granted, isTrue);

    final created = await ctrl.createCalendarEvent(
      title: '牙医复诊',
      start: DateTime.now().add(const Duration(days: 1)),
      end: DateTime.now().add(const Duration(days: 1, hours: 1)),
    );
    expect(created, isTrue);
    expect(
      container.read(careEcosystemProvider).requireValue.upcomingEvents.single.title,
      '牙医复诊',
    );
  });

  test('CareConnectorController isolates mail password in Keystore and enforces HTTPS/loopback for MCP', () async {
    final prefs = _MemPrefs();
    final secrets = _MemSecrets();
    final container = ProviderContainer(
      overrides: [
        carePrefsStoreProvider.overrideWithValue(prefs),
        careSecretStoreProvider.overrideWithValue(secrets),
      ],
    );
    addTearDown(container.dispose);

    final ctrl = container.read(careConnectorProvider.notifier);
    await ctrl.saveMailAccount(
      email: 'me@example.com',
      imapHost: 'imap.example.com',
      smtpHost: 'smtp.example.com',
      appPassword: 'super-secret-mail-pwd',
    );

    // Password must NEVER leak into plain SharedPreferences JSON!
    expect(prefs.map[kCareConnectorsPrefsKey]!.contains('super-secret-mail-pwd'), isFalse);
    expect(secrets.map[kCareMailSecretKey], 'super-secret-mail-pwd');
    expect(container.read(careConnectorProvider).requireValue.mailAccount?.hasPassword, isTrue);

    // Remote plain HTTP MCP must be rejected; HTTPS and loopback HTTP succeed.
    await expectLater(
      () => ctrl.addMcpServer(name: 'Bad', endpointUrl: 'http://remote.example.com/mcp'),
      throwsFormatException,
    );
    final srv = await ctrl.addMcpServer(
      name: 'Local Notes MCP',
      endpointUrl: 'http://127.0.0.1:4100/mcp',
    );
    expect(container.read(careConnectorProvider).requireValue.mcpServers.length, 1);
    await ctrl.toggleMcpServer(srv.id, false);
    expect(container.read(careConnectorProvider).requireValue.mcpServers.single.enabled, isFalse);
  });
}
