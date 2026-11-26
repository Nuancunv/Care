import 'dart:async';
import 'dart:convert';

import 'package:care_app/main.dart';
import 'package:care_app/services/care_m2_bridge.dart';
import 'package:care_app/services/care_m3_bridge.dart';
import 'package:care_app/services/care_m4_bridge.dart';
import 'package:care_app/services/care_platform_bridge.dart';
import 'package:care_app/services/care_share_bridge.dart';
import 'package:care_app/services/care_storage.dart';
import 'package:care_app/services/care_workspace_bridge.dart';
import 'package:care_app/state/care_providers.dart';
import 'package:care_app/ui/automation/care_automation_page.dart';
import 'package:care_app/ui/bots/care_bot_hub_page.dart';
import 'package:care_app/ui/bots/care_bots_page.dart';
import 'package:care_app/ui/care_theme.dart';
import 'package:care_app/ui/chat/care_chat_page.dart';
import 'package:care_app/ui/common/care_markdown_view.dart';
import 'package:care_app/ui/memory/care_memory_page.dart';
import 'package:care_app/ui/settings/care_backup_page.dart';
import 'package:care_app/ui/settings/care_connectors_page.dart';
import 'package:care_app/ui/settings/care_diagnostics_page.dart';
import 'package:care_app/ui/settings/care_settings_page.dart';
import 'package:care_app/ui/today/care_today_page.dart';
import 'package:care_app/ui/workspace/care_workspace_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _MemSecretStore implements CareSecretStore {
  _MemSecretStore([Map<String, String>? seed]) {
    if (seed != null) _data.addAll(seed);
  }
  final Map<String, String> _data = {};
  @override
  Future<void> delete(String key) async => _data.remove(key);
  @override
  Future<String?> read(String key) async => _data[key];
  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}

class _MemPrefsStore implements CarePrefsStore {
  final Map<String, String> _data = {};
  @override
  Future<String?> getString(String key) async => _data[key];
  @override
  Future<void> remove(String key) async => _data.remove(key);
  @override
  Future<void> setString(String key, String value) async => _data[key] = value;
}

class _MemDocStore implements CareDocumentStore {
  final Map<String, String> _docs = {};
  @override
  Future<String?> readDocument(String filename) async => _docs[filename];
  @override
  Future<void> writeDocument(String filename, String content) async =>
      _docs[filename] = content;
}

class _IdleRuntimePlatform implements CareRuntimePlatform {
  final _events = StreamController<Map<String, Object?>>.broadcast();
  @override
  Stream<Map<String, Object?>> events() => _events.stream;
  @override
  Future<List<String>> getLogs({int lines = 200}) async => const [];
  @override
  Future<Map<String, Object?>> getStatus() async => {'phase': 'notInstalled'};
  @override
  Future<void> install() async {}
  @override
  Future<bool> isBatteryExempt() async => false;
  @override
  Future<bool> requestBatteryExempt() async => false;
  @override
  Future<void> start(Map<String, String> env) async {}
  @override
  Future<void> stop() async {}
  void dispose() => _events.close();
}

class _QueueSafetyPlatform implements CareSafetyPlatform {
  _QueueSafetyPlatform(this.items);
  final List<Map<String, Object?>> items;
  final _stream = StreamController<List<Map<String, Object?>>>.broadcast();
  bool? lastApproved;

  @override
  Future<Map<String, Object?>> evaluateAction({
    required String action,
    required String summary,
    String? target,
  }) async =>
      {'allowed': false, 'requiresApproval': true};
  @override
  Future<List<Map<String, Object?>>> getPending() async => List.of(items);
  @override
  Stream<List<Map<String, Object?>>> pendingStream() => _stream.stream;
  @override
  Future<bool> resolve({required String id, required bool approved}) async {
    lastApproved = approved;
    items.removeWhere((e) => e['id'] == id);
    _stream.add(List.of(items));
    return true;
  }

  void dispose() => _stream.close();
}

class _FakeProactivePlatform implements CareProactivePlatform {
  final _events = StreamController<Map<String, Object?>>.broadcast();
  final List<Map<String, Object?>> reminders = [];

  @override
  Stream<Map<String, Object?>> actionEvents() => _events.stream;
  @override
  Future<bool> cancelReminder(String id) async {
    reminders.removeWhere((r) => r['id'] == id);
    return true;
  }

  @override
  Future<List<Map<String, Object?>>> listReminders() async => List.of(reminders);
  @override
  Future<bool> markReminderDone(String id) async {
    for (final r in reminders) {
      if (r['id'] == id) r['done'] = true;
    }
    return true;
  }

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
  }) async {
    reminders.add({
      'id': id,
      'title': title,
      'body': body,
      'triggerAtMs': triggerAtMs,
      'repeatDays': repeatDays,
      'completed': false,
    });
    return true;
  }

  @override
  Future<bool> setIdleSleepMinutes(int minutes) async => true;
  void dispose() => _events.close();
}

class _FakeEcosystemPlatform implements CareEcosystemPlatform {
  bool calendarGranted = false;
  bool noticeEnabled = false;
  List<String> allowList = [];

  @override
  Future<Map<String, bool>> calendarPermissionStatus() async =>
      {'read': calendarGranted, 'write': calendarGranted};
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
      {'created': calendarGranted};
  @override
  Future<List<Map<String, Object?>>> getRecentNotices({int limit = 20}) async =>
      const [];
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
      {'granted': calendarGranted, 'events': const <Object?>[]};
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

class _FakeAutomationPlatform implements CareAutomationPlatform {
  _FakeAutomationPlatform({
    this.a11yEnabled = false,
    this.a11yConnected = false,
    this.manufacturer = 'OPPO',
    this.brand = 'OPPO',
  });

  bool a11yEnabled;
  bool a11yConnected;
  bool emergencyStopped = false;
  String manufacturer;
  String brand;
  Map<String, Object?> screenSummary = const {
    'available': true,
    'blocked': false,
    'packageName': 'com.example.notes',
    'nodes': [
      {'text': '保存', 'desc': '', 'clickable': true, 'editable': false, 'sensitive': false},
      {'text': '标题', 'desc': '', 'clickable': false, 'editable': true, 'sensitive': false},
    ],
  };
  final _events = StreamController<Map<String, Object?>>.broadcast();

  @override
  Future<Map<String, Object?>> captureScreenSummary({int maxNodes = 60}) async =>
      screenSummary;
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
  }) async =>
      {'ok': true};
  @override
  Future<bool> openAccessibilitySettings() async => true;
  @override
  Future<Map<String, Object?>> selfCheck() async => {
        'accessibilityEnabled': a11yEnabled,
        'accessibilityConnected': a11yConnected,
        'shizukuInstalled': false,
        'emergencyStopped': emergencyStopped,
        'manufacturer': manufacturer,
        'brand': brand,
      };
  void dispose() => _events.close();
}

class _FakeVaultPlatform implements CareVaultPlatform {
  final Map<String, String> docs = {};
  @override
  Future<Map<String, Object?>> authenticate({
    required String title,
    required String subtitle,
  }) async =>
      {'authenticated': true};
  @override
  Future<Map<String, Object?>> biometricStatus() async =>
      {'biometricReady': true, 'deviceSecure': true, 'available': true};
  @override
  Future<String> encryptBackup({
    required String passphrase,
    required String payloadJson,
  }) async =>
      jsonEncode({
        'format': 'care-backup-v1',
        'pass': passphrase,
        'ciphertext': base64Encode(utf8.encode(payloadJson)),
      });
  @override
  Future<String> decryptBackup({
    required String passphrase,
    required String envelopeJson,
  }) async {
    final map = jsonDecode(envelopeJson) as Map<String, dynamic>;
    if (map['pass'] != passphrase) throw StateError('wrong passphrase');
    return utf8.decode(base64Decode(map['ciphertext'] as String));
  }

  @override
  Future<String?> readPrivacyDoc({
    required String botId,
    required String filename,
  }) async =>
      docs['$botId/$filename'];
  @override
  Future<bool> writePrivacyDoc({
    required String botId,
    required String filename,
    required String content,
  }) async {
    docs['$botId/$filename'] = content;
    return true;
  }

  @override
  Future<bool> wipePrivacyVault(String botId) async {
    docs.removeWhere((k, _) => k.startsWith('$botId/'));
    return true;
  }
}

class _FakeWorkspacePlatform implements CareWorkspacePlatform {
  final Map<String, String> files = {
    'chief|false|资料库/读书笔记.md': '# 笔记\n复利的力量',
    'chief|false|plan.md': '# 今日计划\n- 写代码',
  };

  @override
  Future<bool> deleteFile({
    required String botId,
    required bool isPrivate,
    required String path,
  }) async {
    files.remove('$botId|$isPrivate|$path');
    return true;
  }

  @override
  Future<List<CareWorkspaceFile>> listFiles({
    required String botId,
    required bool isPrivate,
  }) async =>
      files.entries
          .where((e) => e.key.startsWith('$botId|$isPrivate|'))
          .map(
            (e) => CareWorkspaceFile(
              path: e.key.split('|').last,
              sizeBytes: e.value.length,
              modifiedAt: DateTime(2026, 11, 26),
            ),
          )
          .toList();

  @override
  Future<CarePickedAttachment?> pickAttachment({String mode = 'file'}) async =>
      null;

  @override
  Future<Map<String, Object?>?> importToLibrary({
    required String botId,
    required bool isPrivate,
  }) async =>
      {'ok': true, 'path': '资料库/imported.txt', 'sizeBytes': 10};

  @override
  Future<Map<String, Object?>?> importStagedToLibrary({
    required String botId,
    required bool isPrivate,
    required String stagedPath,
    required String fileName,
  }) async =>
      {'ok': true, 'path': '资料库/$fileName', 'sizeBytes': 10};

  @override
  Future<List<CareLibrarySearchHit>> searchLibrary({
    required String botId,
    required bool isPrivate,
    required String query,
  }) async =>
      const [];

  @override
  Future<String?> readFile({
    required String botId,
    required bool isPrivate,
    required String path,
  }) async =>
      files['$botId|$isPrivate|$path'];

  @override
  Future<Map<String, Object?>> writeFile({
    required String botId,
    required bool isPrivate,
    required String path,
    required String content,
  }) async {
    files['$botId|$isPrivate|$path'] = content;
    return {'ok': true, 'path': path, 'sizeBytes': content.length};
  }

  @override
  Future<bool> openHtmlPreview({
    required String botId,
    required bool isPrivate,
    required String path,
  }) async =>
      true;

  @override
  Future<bool> openWithExternalApp({
    required String botId,
    required bool isPrivate,
    required String path,
  }) async =>
      !isPrivate;
}

class _FakeSharePlatform implements CareSharePlatform {
  final _ctrl = StreamController<CareSharedItem>.broadcast();
  @override
  Stream<CareSharedItem> shareEvents() => _ctrl.stream;
  @override
  Future<CareSharedItem?> takePendingShare() async => null;
  void dispose() => _ctrl.close();
}

/// Lets tests push arbitrary chat states (e.g. streaming deltas) into the UI.
class _ScriptedChat extends CareChatController {
  @override
  CareChatState build() => const CareChatState();

  void emit(CareChatState next) => state = next;
}

class _PreloadedChat extends _ScriptedChat {
  _PreloadedChat(this._initial);
  final CareChatState _initial;

  @override
  CareChatState build() => _initial;
}

Future<void> _pumpApp(
  WidgetTester tester, {
  bool withKey = true,
  List<Map<String, Object?>> pending = const [],
  _ScriptedChat Function()? chat,
  void Function(_QueueSafetyPlatform)? onSafety,
  _FakeAutomationPlatform? automation,
  Widget? home,
}) async {
  final runtime = _IdleRuntimePlatform();
  final safety = _QueueSafetyPlatform(List.of(pending));
  final proactive = _FakeProactivePlatform();
  final ecosystem = _FakeEcosystemPlatform();
  final auto = automation ?? _FakeAutomationPlatform();
  final vault = _FakeVaultPlatform();
  final workspace = _FakeWorkspacePlatform();
  final share = _FakeSharePlatform();
  onSafety?.call(safety);
  addTearDown(() {
    runtime.dispose();
    safety.dispose();
    proactive.dispose();
    auto.dispose();
    share.dispose();
  });

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        careSecretStoreProvider.overrideWithValue(
          _MemSecretStore(
            withKey ? {kCareApiKeyStorageKey: 'sk-ui-test-12345678'} : null,
          ),
        ),
        carePrefsStoreProvider.overrideWithValue(_MemPrefsStore()),
        careDocumentStoreProvider.overrideWithValue(_MemDocStore()),
        careRuntimePlatformProvider.overrideWithValue(runtime),
        careSafetyPlatformProvider.overrideWithValue(safety),
        careProactivePlatformProvider.overrideWithValue(proactive),
        careEcosystemPlatformProvider.overrideWithValue(ecosystem),
        careAutomationPlatformProvider.overrideWithValue(auto),
        careVaultPlatformProvider.overrideWithValue(vault),
        careWorkspacePlatformProvider.overrideWithValue(workspace),
        careSharePlatformProvider.overrideWithValue(share),
        if (chat != null) careChatProvider.overrideWith(chat),
      ],
      child: home == null
          ? const CareApp()
          : MaterialApp(
              theme: CareTheme.light(),
              darkTheme: CareTheme.dark(),
              home: home,
            ),
    ),
  );
}

void main() {
  testWidgets('first run shows friendly onboarding and key entry step', (tester) async {
    await _pumpApp(tester, withKey: false);
    await tester.pumpAndSettle();

    expect(find.text('你好，我是 Care'), findsOneWidget);
    await tester.tap(find.text('开始设置'));
    await tester.pumpAndSettle();
    expect(find.text('连接 DeepSeek'), findsOneWidget);
    expect(find.text('保存并测试连接'), findsOneWidget);
  });

  testWidgets('configured user lands on Bot Hub with single Care Bot hero, hidden Privacy Bot, and 3-way picker', (tester) async {
    await _pumpApp(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(CareBotHubPage), findsOneWidget);
    // Care Bot appears ONLY once (fixed at top hero, NOT duplicated in list below).
    expect(find.text('Care Bot'), findsOneWidget);
    // Privacy Bot is completely hidden by default.
    expect(find.text('Privacy Bot'), findsNothing);
    expect(find.text('隐私 Bot'), findsNothing);
    expect(find.text('搜索 Bot 或聊天记录'), findsOneWidget);
    expect(find.textContaining('PRoot'), findsNothing);
    expect(find.textContaining('Cordis'), findsNothing);

    // Typing "privacy" in search reveals Privacy Bot discreetly.
    await tester.enterText(find.byType(TextField), 'privacy');
    await tester.pump();
    expect(find.text('Privacy Bot'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    // Tap Care Bot hero to enter chat
    await tester.tap(find.text('Care Bot'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(CareChatPage), findsOneWidget);
    expect(find.text('有什么我可以帮你的？'), findsOneWidget);
    expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
    expect(find.byIcon(Icons.mic_rounded), findsNothing);

    // Open + attachment menu and verify 3 options: 选择文件 / 拍照 / 照片
    await tester.tap(find.byTooltip('添加图片或文件'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('选择文件'), findsOneWidget);
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('照片'), findsOneWidget);
  });

  testWidgets('streaming deltas update the draft bubble without rebuilding the page', (tester) async {
    late _ScriptedChat chat;
    await _pumpApp(
      tester,
      chat: () => chat = _ScriptedChat(),
      home: const CareChatPage(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final user = CareChatMessage(
      id: 'u-1',
      role: CareMessageRole.user,
      content: '你好',
      createdAt: DateTime(2026, 11, 25, 9),
    );
    chat.emit(CareChatState(messages: [user], isStreaming: true));
    await tester.pump();

    final pageElement = tester.element(find.byType(CareChatPage));
    final pageWidgetBefore = pageElement.widget;
    var pageBuilds = 0;
    // A rebuild of the outer page would first mark its element dirty; it must
    // stay clean across every per-token delta frame.
    for (final delta in ['今', '今天', '今天天气', '今天天气不错']) {
      chat.emit(CareChatState(
        messages: [user],
        isStreaming: true,
        draftText: delta,
      ));
      if (pageElement.dirty) pageBuilds++;
      await tester.pump();
    }
    expect(pageBuilds, 0, reason: 'outer chat page must not rebuild on deltas');
    expect(identical(pageElement.widget, pageWidgetBefore), isTrue);
    expect(find.text('今天天气不错', findRichText: true), findsOneWidget);
    expect(find.text('你好'), findsOneWidget);

    chat.emit(CareChatState(
      messages: [
        user,
        CareChatMessage(
          id: 'a-1',
          role: CareMessageRole.assistant,
          content: '今天天气不错！',
          createdAt: DateTime(2026, 11, 25, 9, 1),
        ),
      ],
    ));
    await tester.pump();
    expect(find.text('今天天气不错！', findRichText: true), findsOneWidget);
    expect(find.text('今天天气不错', findRichText: true), findsNothing);
  });

  testWidgets('pending SafetyGate request raises approval sheet that resolves natively', (tester) async {
    late _QueueSafetyPlatform safety;
    await _pumpApp(
      tester,
      pending: [
        {
          'id': 'req-9',
          'action': 'send_email',
          'summary': '把周报发送给 boss@example.com',
          'target': 'mail',
          'riskLevel': 'L2',
          'createdAtMs': 1764032400000,
        },
      ],
      onSafety: (s) => safety = s,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('需要你确认'), findsOneWidget);
    expect(find.text('Care 想要替你发送邮件'), findsOneWidget);

    await tester.tap(find.text('允许执行'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(safety.lastApproved, isTrue);
    expect(find.text('需要你确认'), findsNothing);
  });

  testWidgets('SafetyGate automation request supports deny + emergency stop', (tester) async {
    late _QueueSafetyPlatform safety;
    final auto = _FakeAutomationPlatform(a11yEnabled: true, a11yConnected: true);
    await _pumpApp(
      tester,
      automation: auto,
      pending: [
        {
          'id': 'req-a11y',
          'action': 'accessibility_click',
          'summary': '在微信中点击发送按钮',
          'target': 'com.tencent.mm',
          'riskLevel': 'L2',
          'createdAtMs': 1764032400000,
        },
      ],
      onSafety: (s) => safety = s,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('高风险 · 单次授权'), findsOneWidget);
    expect(find.text('拒绝并紧急停止后续操作'), findsOneWidget);

    await tester.tap(find.text('拒绝并紧急停止后续操作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(safety.lastApproved, isFalse);
    expect(auto.emergencyStopped, isTrue);
  });

  testWidgets('Today hub generates briefing and hides empty scheduled tasks by default', (tester) async {
    await _pumpApp(tester, home: const CareTodayPage());
    await tester.pumpAndSettle();

    expect(find.text('今日'), findsOneWidget);
    expect(find.text('常用例程'), findsNothing);
    expect(find.text('晚间通知与待办整理'), findsNothing);
    expect(find.textContaining('PRoot'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, '早间简报'));
    await tester.pumpAndSettle();
    expect(find.text('聊聊这份简报'), findsOneWidget);
  });

  testWidgets('Memory page renders transparent tabs and saves edits', (tester) async {
    await _pumpApp(tester, home: const CareMemoryPage());
    await tester.pumpAndSettle();

    expect(find.text('我的记忆'), findsOneWidget);
    expect(find.text('Care 的性格'), findsOneWidget);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '# 我的记忆\n- 喜欢手冲咖啡');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('喜欢手冲咖啡', findRichText: true), findsOneWidget);
  });

  testWidgets('Automation page shows ColorOS hint, empty scheduled tasks, create flow, and screen inspect', (tester) async {
    final auto = _FakeAutomationPlatform(
      a11yEnabled: false,
      a11yConnected: false,
      manufacturer: 'OPPO',
      brand: 'OPPO',
    );
    await _pumpApp(tester, automation: auto, home: const CareAutomationPage());
    await tester.pumpAndSettle();

    expect(find.textContaining('ColorOS 提示'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('定时任务'), 200);
    expect(find.text('暂无定时任务'), findsOneWidget);

    // Create a new scheduled task and expand its steps
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '周日复盘');
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();
    expect(find.text('周日复盘'), findsOneWidget);
    await tester.tap(find.text('周日复盘'));
    await tester.pumpAndSettle();
    expect(find.text('读取近期日历安排'), findsOneWidget);

    // Enable accessibility and verify screen inspect card
    auto.a11yEnabled = true;
    auto.a11yConnected = true;
    await tester.tap(find.byTooltip('重新检测'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('脱敏界面读取自检'), findsOneWidget);
    await tester.tap(find.text('测试读取'));
    await tester.pumpAndSettle();
    expect(find.textContaining('识别到 2 个脱敏界面节点'), findsOneWidget);
  });

  testWidgets('Settings removes legacy engine/filler tiles and Diagnostics shows native health', (tester) async {
    await _pumpApp(tester, home: const CareSettingsPage());
    await tester.pumpAndSettle();

    expect(find.textContaining('PRoot'), findsNothing);
    await tester.scrollUntilVisible(find.text('Privacy Bot 隐藏入口'), 200);
    expect(find.text('Privacy Bot 隐藏入口'), findsOneWidget);
    expect(find.text('本机引擎状态'), findsNothing);
    expect(find.text('你的数据只属于你'), findsNothing);

    await _pumpApp(tester, home: const CareDiagnosticsPage());
    await tester.pumpAndSettle();
    expect(find.text('Care 原生直连引擎'), findsOneWidget);
    expect(find.textContaining('notBundled'), findsNothing);

    await _pumpApp(tester, home: const CareConnectorsPage());
    await tester.pumpAndSettle();
    expect(find.text('还没有扩展服务'), findsOneWidget);
  });

  testWidgets('CareMarkdownView renders task checkboxes and fenced code blocks', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CareTheme.light(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: CareMarkdownView(
              markdown: '- [x] 完成早间简报\n- [ ] 回复邮件\n\n```dart\nprint("Care");\n```',
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
    expect(find.byTooltip('复制代码'), findsOneWidget);
    expect(find.text('dart'), findsOneWidget);
  });

  testWidgets('Bots page spawns specialist and unlocks/locks Privacy Bot', (tester) async {
    await _pumpApp(tester, home: const CareBotsPage());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Care Bot · 主 Bot'), findsOneWidget);
    await tester.tap(find.text('+ 行程规划 Bot'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('行程规划 Bot'), findsOneWidget);

    await tester.ensureVisible(find.text('解锁隐私空间'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('解锁隐私空间'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Privacy Bot · 已解锁'), findsOneWidget);
    expect(find.text('进入私密对话'), findsOneWidget);

    await tester.ensureVisible(find.text('上锁'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('上锁'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Privacy Bot（已锁定）'), findsOneWidget);
  });

  testWidgets('Backup page generates local encrypted backup without filler banner', (tester) async {
    await _pumpApp(tester, home: const CareBackupPage());
    await tester.pumpAndSettle();

    expect(find.text('数据完全由你掌控，零云端中转'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'care-secret-99');
    await tester.tap(find.widgetWithText(FilledButton, '生成加密备份'));
    await tester.pumpAndSettle();

    expect(find.text('复制加密备份'), findsOneWidget);
  });

  testWidgets('Reasoning starts collapsed and expands only when tapped', (tester) async {
    late _ScriptedChat chat;
    await _pumpApp(
      tester,
      chat: () => chat = _ScriptedChat(),
      home: const CareChatPage(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Flash · 低思考'), findsOneWidget);
    expect(find.byTooltip('添加图片或文件'), findsOneWidget);

    chat.emit(CareChatState(
      messages: [
        CareChatMessage(
          id: 'u-r',
          role: CareMessageRole.user,
          content: '解释一下',
          createdAt: DateTime(2026, 11, 26, 9),
        ),
      ],
      isStreaming: true,
      draftReasoning: '内部隐藏思考细节 ABC123',
    ));
    await tester.pump();
    expect(find.text('内部隐藏思考细节 ABC123'), findsNothing);
    expect(find.text('正在思考…'), findsOneWidget);

    await tester.tap(find.text('正在思考…'));
    await tester.pump();
    expect(find.text('内部隐藏思考细节 ABC123'), findsOneWidget);
  });

  testWidgets('Workspace page displays 资料库 with Notebook Studio chips and 工作区文件 tabs', (tester) async {
    await _pumpApp(tester, home: const CareWorkspacePage());
    await tester.pumpAndSettle();
    expect(find.text('资料库'), findsOneWidget);
    expect(find.text('工作区文件'), findsOneWidget);
    expect(find.text('读书笔记.md'), findsOneWidget);
    expect(find.text('生成翻页闪卡'), findsOneWidget);
    expect(find.text('生成交互测验'), findsOneWidget);
    expect(find.text('生成一页导图'), findsOneWidget);
    expect(find.byTooltip('默认应用打开'), findsWidgets);

    await tester.tap(find.text('工作区文件'));
    await tester.pumpAndSettle();
    expect(find.text('plan.md'), findsOneWidget);
  });

  testWidgets('Chat reply renders inline HTML file artifact card with render and default-app actions', (tester) async {
    late _ScriptedChat chat;
    await _pumpApp(
      tester,
      chat: () => chat = _ScriptedChat(),
      home: const CareChatPage(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    chat.emit(CareChatState(
      messages: [
        CareChatMessage(
          id: 'u-html',
          role: CareMessageRole.user,
          content: '帮我写一个番茄钟网页',
          createdAt: DateTime(2026, 11, 26, 10),
        ),
        CareChatMessage(
          id: 'a-html',
          role: CareMessageRole.assistant,
          content: '已经为你写好了番茄钟网页！',
          createdAt: DateTime(2026, 11, 26, 10, 1),
          toolActivities: const [
            CareToolActivity(
              tool: 'workspace_write',
              label: '已写入 pomodoro.html',
              workspacePath: 'pomodoro.html',
            ),
          ],
        ),
      ],
    ));
    await tester.pump();
    expect(find.text('pomodoro.html'), findsOneWidget);
    expect(find.text('渲染网页'), findsOneWidget);
    expect(find.text('看源码'), findsOneWidget);
    expect(find.text('默认应用打开'), findsOneWidget);
  });

  testWidgets('Re-entering chat with long history jumps to latest message instead of top', (tester) async {
    final longHistory = [
      for (var i = 0; i < 24; i++)
        CareChatMessage(
          id: 'hist-$i',
          role: i.isEven ? CareMessageRole.user : CareMessageRole.assistant,
          content: '第 $i 条历史消息，用于验证切回 Bot 时自动定位到最新对话位置。',
          createdAt: DateTime(2026, 11, 26, 10, i),
        ),
    ];
    await _pumpApp(
      tester,
      chat: () => _PreloadedChat(CareChatState(messages: longHistory)),
      home: const CareChatPage(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.pixels, greaterThan(0));
    expect(find.textContaining('第 23 条历史消息', findRichText: true), findsOneWidget);
  });
}
