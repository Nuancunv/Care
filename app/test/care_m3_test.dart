import 'dart:async';

import 'package:care_app/services/care_m2_bridge.dart';
import 'package:care_app/services/care_m3_bridge.dart';
import 'package:care_app/services/care_platform_bridge.dart';
import 'package:care_app/services/care_storage.dart';
import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

class _FakeSafety implements CareSafetyPlatform {
  final _stream = StreamController<List<Map<String, Object?>>>.broadcast();
  final List<Map<String, Object?>> pending = [];

  @override
  Future<Map<String, Object?>> evaluateAction({
    required String action,
    required String summary,
    String? target,
  }) async {
    final req = {
      'id': 'gate-${pending.length + 1}',
      'action': action,
      'summary': summary,
      'target': target,
      'riskLevel': 'L2',
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    pending.add(req);
    _stream.add(List.of(pending));
    return {'allowed': false, 'requiresApproval': true, 'request': req};
  }

  @override
  Future<List<Map<String, Object?>>> getPending() async => List.of(pending);

  @override
  Stream<List<Map<String, Object?>>> pendingStream() => _stream.stream;

  @override
  Future<bool> resolve({required String id, required bool approved}) async {
    pending.removeWhere((e) => e['id'] == id);
    _stream.add(List.of(pending));
    return true;
  }

  void dispose() => _stream.close();
}

class _FakeAutomation implements CareAutomationPlatform {
  final _events = StreamController<Map<String, Object?>>.broadcast();
  bool emergencyStopped = false;
  int executedCount = 0;

  @override
  Future<Map<String, Object?>> captureScreenSummary({int maxNodes = 60}) async => {
        'available': true,
        'blocked': false,
        'packageName': 'com.example.notes',
        'nodes': [
          {
            'text': '保存草稿',
            'desc': '',
            'clickable': true,
            'editable': false,
            'sensitive': false,
          },
        ],
      };

  @override
  Future<bool> clearEmergencyStop() async {
    emergencyStopped = false;
    return true;
  }

  @override
  Future<bool> emergencyStop() async {
    emergencyStopped = true;
    return true;
  }

  @override
  Stream<Map<String, Object?>> events() => _events.stream;

  @override
  Future<Map<String, Object?>> executeStep({
    required String action,
    required String? approvalToken,
    String? nodeText,
    double? x,
    double? y,
    String? text,
  }) async {
    if (emergencyStopped) {
      return {'ok': false, 'reason': 'Emergency stop active'};
    }
    if (approvalToken == null || !approvalToken.startsWith('care-gate-')) {
      return {'ok': false, 'blocked': true, 'reason': 'Invalid approval token'};
    }
    executedCount++;
    return {'ok': true, 'action': action};
  }

  @override
  Future<bool> openAccessibilitySettings() async => true;

  @override
  Future<Map<String, Object?>> selfCheck() async => {
        'accessibilityEnabled': true,
        'accessibilityConnected': true,
        'shizukuInstalled': false,
        'emergencyStopped': emergencyStopped,
        'manufacturer': 'OPPO',
        'brand': 'OPPO',
      };

  void dispose() => _events.close();
}

class _StubEcosystem implements CareEcosystemPlatform {
  @override
  Future<Map<String, bool>> calendarPermissionStatus() async => {'read': true, 'write': true};
  @override
  Future<bool> clearNotices() async => true;
  @override
  Future<Map<String, Object?>> createCalendarEvent({
    required String title,
    required int startMs,
    required int endMs,
    String? location,
    String? notes,
  }) async =>
      {'created': true};
  @override
  Future<List<Map<String, Object?>>> getRecentNotices({int limit = 20}) async => const [];
  @override
  Future<Map<String, Object?>> noticeAccessStatus() async => {'enabled': false, 'allowList': <String>[]};
  @override
  Future<bool> openNoticeAccessSettings() async => true;
  @override
  Future<Map<String, Object?>> readCalendarEvents({
    required int startMs,
    required int endMs,
  }) async =>
      {'granted': true, 'events': <Object?>[]};
  @override
  Future<bool> requestCalendarPermission() async => true;
  @override
  Future<bool> setNoticeAllowList(List<String> packages) async => true;
}

class _StubProactive implements CareProactivePlatform {
  @override
  Stream<Map<String, Object?>> actionEvents() => const Stream.empty();
  @override
  Future<bool> cancelReminder(String id) async => true;
  @override
  Future<List<Map<String, Object?>>> listReminders() async => const [];
  @override
  Future<bool> markReminderDone(String id) async => true;
  @override
  Future<bool> notifyNow({
    required String id,
    required String kind,
    required String title,
    required String body,
  }) async =>
      true;
  @override
  Future<bool> scheduleBriefing({
    required String kind,
    required bool enabled,
    required String time,
    required String quietStart,
    required String quietEnd,
  }) async =>
      true;
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
      true;
  @override
  Future<bool> setIdleSleepMinutes(int minutes) async => true;
}

void main() {
  test('CareAutomationController gates L2 actions through SafetyGate and supports emergency stop', () async {
    final safety = _FakeSafety();
    final auto = _FakeAutomation();
    final container = ProviderContainer(
      overrides: [
        careSafetyPlatformProvider.overrideWithValue(safety),
        careAutomationPlatformProvider.overrideWithValue(auto),
      ],
    );
    addTearDown(() {
      container.dispose();
      safety.dispose();
      auto.dispose();
    });

    final ctrl = container.read(careAutomationProvider.notifier);
    final check = await ctrl.refreshSelfCheck();
    expect(check.ready, isTrue);
    expect(check.manufacturer, 'OPPO');

    // Without approvalToken, L2 click MUST NOT execute and MUST enqueue a SafetyGate approval!
    final unapproved = await ctrl.executeGatedStep(
      action: 'accessibility_click',
      summary: '点击保存草稿',
      nodeText: '保存草稿',
    );
    expect(unapproved, isFalse);
    expect(auto.executedCount, 0);
    expect(container.read(careSafetyProvider).pending.length, 1);

    // With valid native approvalToken, execution succeeds
    final approved = await ctrl.executeGatedStep(
      action: 'accessibility_click',
      summary: '点击保存草稿',
      nodeText: '保存草稿',
      approvalToken: 'care-gate-valid-1',
    );
    expect(approved, isTrue);
    expect(auto.executedCount, 1);

    // Emergency stop blocks any subsequent execution immediately
    await ctrl.emergencyStop();
    expect(container.read(careAutomationProvider).emergencyStopped, isTrue);
    final blockedByStop = await ctrl.executeGatedStep(
      action: 'accessibility_click',
      summary: '再次点击',
      approvalToken: 'care-gate-valid-2',
    );
    expect(blockedByStop, isFalse);
    expect(auto.executedCount, 1);
  });

  test('CareRoutineController starts empty by default, executes safe tasks, and pauses high-risk steps for SafetyGate', () async {
    final prefs = _MemPrefs();
    final docs = _MemDocs();
    final safety = _FakeSafety();
    final auto = _FakeAutomation();
    final container = ProviderContainer(
      overrides: [
        carePrefsStoreProvider.overrideWithValue(prefs),
        careDocumentStoreProvider.overrideWithValue(docs),
        careSafetyPlatformProvider.overrideWithValue(safety),
        careAutomationPlatformProvider.overrideWithValue(auto),
        careEcosystemPlatformProvider.overrideWithValue(_StubEcosystem()),
        careProactivePlatformProvider.overrideWithValue(_StubProactive()),
      ],
    );
    addTearDown(() {
      container.dispose();
      safety.dispose();
      auto.dispose();
    });

    final initial = await container.read(careRoutineProvider.future);
    expect(initial.routines, isEmpty);

    // Create and run a safe scheduled task end-to-end
    final ctrl = container.read(careRoutineProvider.notifier);
    final safeTask = await ctrl.createRoutine(
      name: '晚间待办整理',
      scheduleTimeHHmm: '21:00',
      enabled: true,
      steps: const [
        CareRoutineStep(id: 's1', description: '读取日历', action: 'collect_calendar'),
        CareRoutineStep(id: 's2', description: '读取记忆', action: 'collect_memory'),
      ],
    );
    final res1 = await ctrl.runRoutine(safeTask.id);
    expect(res1.completed, isTrue);
    expect(res1.pausedForApproval, isFalse);

    // Create a custom task containing an L2 cross-app write step -> MUST pause for native SafetyGate!
    final custom = await ctrl.createRoutine(
      name: '自动整理发票发草稿',
      steps: const [
        CareRoutineStep(id: 's1', description: '读取记忆', action: 'collect_memory'),
        CareRoutineStep(
          id: 's2',
          description: '在目标 App 点击发送草稿',
          action: 'accessibility_click',
          params: {'targetPackage': 'com.example.mail'},
        ),
      ],
    );
    final res2 = await ctrl.runRoutine(custom.id);
    expect(res2.completed, isFalse);
    expect(res2.pausedForApproval, isTrue);
    expect(container.read(careSafetyProvider).pending.length, 1);
  });
}
