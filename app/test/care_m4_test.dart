import 'dart:async';
import 'dart:convert';

import 'package:care_app/services/care_deepseek_direct.dart';
import 'package:care_app/services/care_m2_bridge.dart';
import 'package:care_app/services/care_m4_bridge.dart';
import 'package:care_app/services/care_platform_bridge.dart';
import 'package:care_app/services/care_storage.dart';
import 'package:care_app/services/care_workspace_bridge.dart';
import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemSecrets implements CareSecretStore {
  final Map<String, String> data = {
    kCareApiKeyStorageKey: 'sk-super-secret-never-export-9999',
  };
  @override
  Future<void> delete(String key) async => data.remove(key);
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

class _MemPrefs implements CarePrefsStore {
  final Map<String, String> data = {};
  @override
  Future<String?> getString(String key) async => data[key];
  @override
  Future<void> remove(String key) async => data.remove(key);
  @override
  Future<void> setString(String key, String value) async => data[key] = value;
}

class _MemDocs implements CareDocumentStore {
  final Map<String, String> docs = {};
  @override
  Future<String?> readDocument(String filename) async => docs[filename];
  @override
  Future<void> writeDocument(String filename, String content) async =>
      docs[filename] = content;
}

class _FakeSafety implements CareSafetyPlatform {
  final List<Map<String, Object?>> pending = [];
  final _ctrl = StreamController<List<Map<String, Object?>>>.broadcast();

  @override
  Future<Map<String, Object?>> evaluateAction({
    required String action,
    required String summary,
    String? target,
  }) async {
    pending.add({
      'id': 'req-${pending.length + 1}',
      'action': action,
      'summary': summary,
      'target': target,
      'riskLevel': 'L2',
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    _ctrl.add(List.of(pending));
    return {'allowed': false, 'requiresApproval': true};
  }

  @override
  Future<List<Map<String, Object?>>> getPending() async => List.of(pending);
  @override
  Stream<List<Map<String, Object?>>> pendingStream() => _ctrl.stream;
  @override
  Future<bool> resolve({required String id, required bool approved}) async => true;
  void dispose() => _ctrl.close();
}

class _FakeProactive implements CareProactivePlatform {
  final _ctrl = StreamController<Map<String, Object?>>.broadcast();
  @override
  Stream<Map<String, Object?>> actionEvents() => _ctrl.stream;
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
  void dispose() => _ctrl.close();
}

class _FakeVault implements CareVaultPlatform {
  bool authResult = true;
  final Map<String, String> isolatedFiles = {};

  @override
  Future<Map<String, Object?>> authenticate({
    required String title,
    required String subtitle,
  }) async =>
      {'authenticated': authResult};

  @override
  Future<Map<String, Object?>> biometricStatus() async =>
      {'biometricReady': true, 'deviceSecure': true, 'available': true};

  @override
  Future<String> encryptBackup({
    required String passphrase,
    required String payloadJson,
  }) async {
    return jsonEncode({
      'format': 'care-backup-v1',
      'pass': passphrase,
      'ciphertext': base64Encode(utf8.encode(payloadJson)),
    });
  }

  @override
  Future<String> decryptBackup({
    required String passphrase,
    required String envelopeJson,
  }) async {
    final map = jsonDecode(envelopeJson) as Map<String, dynamic>;
    if (map['pass'] != passphrase) {
      throw StateError('Wrong passphrase');
    }
    return utf8.decode(base64Decode(map['ciphertext'] as String));
  }

  @override
  Future<String?> readPrivacyDoc({
    required String botId,
    required String filename,
  }) async =>
      isolatedFiles['$botId/$filename'];

  @override
  Future<bool> writePrivacyDoc({
    required String botId,
    required String filename,
    required String content,
  }) async {
    isolatedFiles['$botId/$filename'] = content;
    return true;
  }

  @override
  Future<bool> wipePrivacyVault(String botId) async {
    isolatedFiles.removeWhere((k, _) => k.startsWith('$botId/'));
    return true;
  }
}

class _FakeWorkspace implements CareWorkspacePlatform {
  final Map<String, String> files = {};

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
  }) async {
    files['$botId|$isPrivate|资料库/讲义.md'] = '# 线性代数\n特征值与特征向量定义';
    return {'ok': true, 'path': '资料库/讲义.md', 'sizeBytes': 32};
  }

  @override
  Future<Map<String, Object?>?> importStagedToLibrary({
    required String botId,
    required bool isPrivate,
    required String stagedPath,
    required String fileName,
  }) async {
    files['$botId|$isPrivate|资料库/$fileName'] = 'staged:$stagedPath';
    return {'ok': true, 'path': '资料库/$fileName', 'sizeBytes': 16};
  }

  @override
  Future<List<CareLibrarySearchHit>> searchLibrary({
    required String botId,
    required bool isPrivate,
    required String query,
  }) async {
    final prefix = '$botId|$isPrivate|资料库/';
    final hits = <CareLibrarySearchHit>[];
    for (final e in files.entries) {
      if (!e.key.startsWith(prefix)) continue;
      if (query.isEmpty || e.value.contains(query) || e.key.contains(query)) {
        hits.add(
          CareLibrarySearchHit(
            path: e.key.split('|').last,
            snippet: e.value,
          ),
        );
      }
    }
    return hits;
  }

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
      files.containsKey('$botId|$isPrivate|$path');

  @override
  Future<bool> openWithExternalApp({
    required String botId,
    required bool isPrivate,
    required String path,
  }) async =>
      !isPrivate && files.containsKey('$botId|$isPrivate|$path');
}

class _CapturingDirectClient extends CareDeepSeekDirectClient {
  List<Map<String, Object?>>? lastMessages;
  String? lastModel;
  String? lastEffort;
  int callCount = 0;
  bool emitWorkspaceWriteOnFirstCall = false;
  bool emitBotCreateOnFirstCall = false;
  bool emitKnowledgeSearchOnFirstCall = false;

  @override
  Stream<DirectStreamChunk> streamChat({
    required String apiKey,
    required String model,
    required List<Map<String, Object?>> messages,
    String baseUrl = CareDeepSeekDirectClient.defaultBaseUrl,
    String? reasoningEffort,
    List<Map<String, Object?>>? tools,
  }) async* {
    callCount++;
    lastMessages = messages;
    lastModel = model;
    lastEffort = reasoningEffort;
    if (emitWorkspaceWriteOnFirstCall && callCount == 1) {
      yield const DirectStreamChunk(
        toolCallDeltas: [
          DirectToolCallDelta(
            index: 0,
            id: 'call_ws_1',
            name: 'workspace_write',
            argumentsDelta: '{"path":"hello.py","content":"print(\\"Care\\")"}',
          ),
        ],
        finishReason: 'tool_calls',
      );
      return;
    }
    if (emitBotCreateOnFirstCall && callCount == 1) {
      yield const DirectStreamChunk(
        toolCallDeltas: [
          DirectToolCallDelta(
            index: 0,
            id: 'call_bot_1',
            name: 'bot_create',
            argumentsDelta:
                '{"name":"Finance","role":"财经与资产复盘","avatar_shape":"star","avatar_color":"coral"}',
          ),
        ],
        finishReason: 'tool_calls',
      );
      return;
    }
    if (emitKnowledgeSearchOnFirstCall && callCount == 1) {
      yield const DirectStreamChunk(
        toolCallDeltas: [
          DirectToolCallDelta(
            index: 0,
            id: 'call_kb_1',
            name: 'knowledge_search',
            argumentsDelta: '{"query":"特征值"}',
          ),
        ],
        finishReason: 'tool_calls',
      );
      return;
    }
    yield const DirectStreamChunk(contentDelta: '收到，已严格隔离处理。');
  }
}

class _IdleRuntime implements CareRuntimePlatform {
  final _ctrl = StreamController<Map<String, Object?>>.broadcast();
  @override
  Stream<Map<String, Object?>> events() => _ctrl.stream;
  @override
  Future<List<String>> getLogs({int lines = 200}) async => const [];
  @override
  Future<Map<String, Object?>> getStatus() async => {'phase': 'notBundled'};
  @override
  Future<void> install() async {}
  @override
  Future<bool> isBatteryExempt() async => true;
  @override
  Future<bool> requestBatteryExempt() async => true;
  @override
  Future<void> start(Map<String, String> env) async {}
  @override
  Future<void> stop() async {}
  void dispose() => _ctrl.close();
}

void main() {
  test('CareBotsController isolates Privacy Bot physically and gates cross-bot export', () async {
    final vault = _FakeVault();
    final safety = _FakeSafety();
    final docs = _MemDocs();
    final direct = _CapturingDirectClient();
    final runtime = _IdleRuntime();
    final container = ProviderContainer(
      overrides: [
        careSecretStoreProvider.overrideWithValue(_MemSecrets()),
        carePrefsStoreProvider.overrideWithValue(_MemPrefs()),
        careDocumentStoreProvider.overrideWithValue(docs),
        careVaultPlatformProvider.overrideWithValue(vault),
        careSafetyPlatformProvider.overrideWithValue(safety),
        careDirectClientProvider.overrideWithValue(direct),
        careRuntimePlatformProvider.overrideWithValue(runtime),
      ],
    );
    addTearDown(() {
      safety.dispose();
      runtime.dispose();
      container.dispose();
    });

    await container.read(careMemoryProvider.notifier).saveMemory('# 公共记忆\n- 喜欢喝拿铁');
    final initial = await container.read(careBotsProvider.future);
    expect(initial.activeBotId, kCareChiefBotId);
    expect(initial.privacyUnlocked, isFalse);

    // Locked Privacy Bot cannot be selected.
    final blockedSelect = await container
        .read(careBotsProvider.notifier)
        .selectActiveBot(kCarePrivacyBotId);
    expect(blockedSelect, isFalse);

    // Spawn specialist from template.
    final planner = await container
        .read(careBotsProvider.notifier)
        .spawnFromTemplate('travel-planner');
    expect(planner.name, '行程规划 Bot');

    // Unlock Privacy Vault via native biometric, write private note, chat under isolation.
    final unlocked =
        await container.read(careBotsProvider.notifier).unlockPrivacyVault();
    expect(unlocked, isTrue);
    await container
        .read(careBotsProvider.notifier)
        .savePrivacyMemory('# 私密笔记\n- 体检胆固醇偏高');
    expect(
      vault.isolatedFiles['$kCarePrivacyBotId/$kCarePrivacyMemoryFile'],
      contains('体检胆固醇偏高'),
    );
    expect(docs.docs['MEMORY.md'], isNot(contains('体检胆固醇偏高')));

    expect(
      await container
          .read(careBotsProvider.notifier)
          .selectActiveBot(kCarePrivacyBotId),
      isTrue,
    );
    await container.read(careChatProvider.notifier).sendMessage('帮我记一下复查日期');
    final sysPrompt = direct.lastMessages!.first['content']! as String;
    expect(sysPrompt, contains('体检胆固醇偏高'));
    expect(sysPrompt, isNot(contains('喜欢喝拿铁')));

    // Cross-bot export MUST trigger native SafetyGate approval.
    final exportedImmediately = await container
        .read(careBotsProvider.notifier)
        .requestPrivacyExport(summary: '导出复查摘要给主管家');
    expect(exportedImmediately, isFalse);
    expect(safety.pending.length, 1);
    expect(safety.pending.first['action'], 'privacy_cross_bot_export');

    // Locking clears volatile memory & returns active bot to Chief.
    container.read(careBotsProvider.notifier).lockPrivacyVault();
    final afterLock = container.read(careBotsProvider).value!;
    expect(afterLock.privacyUnlocked, isFalse);
    expect(afterLock.privacyMemoryMarkdown, isEmpty);
    expect(afterLock.activeBotId, kCareChiefBotId);
  });

  test('CareBackupController encrypts/restores locally and never exports API keys or Privacy Vault', () async {
    final vault = _FakeVault();
    final proactive = _FakeProactive();
    final container = ProviderContainer(
      overrides: [
        careSecretStoreProvider.overrideWithValue(_MemSecrets()),
        carePrefsStoreProvider.overrideWithValue(_MemPrefs()),
        careDocumentStoreProvider.overrideWithValue(_MemDocs()),
        careVaultPlatformProvider.overrideWithValue(vault),
        careProactivePlatformProvider.overrideWithValue(proactive),
      ],
    );
    addTearDown(() {
      proactive.dispose();
      container.dispose();
    });

    await container.read(careMemoryProvider.notifier).saveSoul('# 自定义性格\n温和简洁');
    await container.read(careMemoryProvider.notifier).saveMemory('# 长期记忆\n- 养了一只橘猫');
    await container.read(careBotsProvider.notifier).spawnFromTemplate('health-coach');
    await container.read(careBotsProvider.notifier).unlockPrivacyVault();
    await container
        .read(careBotsProvider.notifier)
        .savePrivacyMemory('# 绝密财务\n- 银行卡密码提示');

    // Passphrase too short must throw.
    await expectLater(
      container.read(careBackupProvider.notifier).exportEncryptedBackup('123'),
      throwsFormatException,
    );

    final envelope = await container
        .read(careBackupProvider.notifier)
        .exportEncryptedBackup('care-pass-2026');
    final rawPlain = await vault.decryptBackup(
      passphrase: 'care-pass-2026',
      envelopeJson: envelope,
    );
    expect(rawPlain, contains('养了一只橘猫'));
    expect(rawPlain, contains('健康教练 Bot'));
    expect(rawPlain, isNot(contains('sk-super-secret')));
    expect(rawPlain, isNot(contains('绝密财务')));

    // Overwrite local memory, then restore from encrypted backup.
    await container.read(careMemoryProvider.notifier).saveMemory('# 已被覆盖');
    final summary = await container
        .read(careBackupProvider.notifier)
        .importEncryptedBackup(
          passphrase: 'care-pass-2026',
          envelopeJson: envelope,
        );
    expect(summary.includesSecrets, isFalse);
    expect(summary.specialistCount, 1);
    final restoredMem = await container.read(careMemoryProvider.future);
    expect(restoredMem.memoryMarkdown, contains('养了一只橘猫'));
  });

  test('Agent tool loop writes to local workspace and default briefings are off (zero auto-billing)', () async {
    expect(const CareBriefingConfig().morningEnabled, isFalse);
    expect(const CareBriefingConfig().eveningEnabled, isFalse);

    final ws = _FakeWorkspace();
    final direct = _CapturingDirectClient()..emitWorkspaceWriteOnFirstCall = true;
    final runtime = _IdleRuntime();
    final vault = _FakeVault();
    final container = ProviderContainer(
      overrides: [
        careSecretStoreProvider.overrideWithValue(_MemSecrets()),
        carePrefsStoreProvider.overrideWithValue(_MemPrefs()),
        careDocumentStoreProvider.overrideWithValue(_MemDocs()),
        careWorkspacePlatformProvider.overrideWithValue(ws),
        careDirectClientProvider.overrideWithValue(direct),
        careRuntimePlatformProvider.overrideWithValue(runtime),
        careVaultPlatformProvider.overrideWithValue(vault),
      ],
    );
    addTearDown(() {
      runtime.dispose();
      container.dispose();
    });

    await container.read(careChatProvider.notifier).sendMessage('帮我写一个 hello.py');
    expect(direct.callCount, 2);
    expect(direct.lastModel, kCareDefaultModel);
    expect(direct.lastEffort, kCareDefaultEffort);
    expect(ws.files['chief|false|hello.py'], 'print("Care")');
    final chat = container.read(careChatProvider);
    expect(chat.messages.last.toolActivities.single.workspacePath, 'hello.py');
  });

  test('New specialist bot Study seeds a domain-tailored opening greeting', () async {
    final container = ProviderContainer(
      overrides: [
        careSecretStoreProvider.overrideWithValue(_MemSecrets()),
        carePrefsStoreProvider.overrideWithValue(_MemPrefs()),
        careDocumentStoreProvider.overrideWithValue(_MemDocs()),
        careVaultPlatformProvider.overrideWithValue(_FakeVault()),
      ],
    );
    addTearDown(container.dispose);

    final study = await container.read(careBotsProvider.notifier).spawnSpecialist(
          name: 'Study',
          roleTitle: '学习搭档',
          systemPrompt: '',
        );
    container.read(careChatProvider.notifier).syncActiveBot(study.id, profile: study);
    final chat = container.read(careChatProvider);
    expect(chat.messages.length, 1);
    expect(chat.messages.first.role, CareMessageRole.assistant);
    expect(chat.messages.first.content, contains('Study'));
    expect(chat.messages.first.content, contains('学习'));
  });

  test('Chat history persists across cold restarts while Privacy Bot stays strictly unpersisted', () async {
    final sharedDocs = _MemDocs();
    final direct = _CapturingDirectClient();
    final runtime = _IdleRuntime();
    final vault = _FakeVault();

    final c1 = ProviderContainer(
      overrides: [
        careSecretStoreProvider.overrideWithValue(_MemSecrets()),
        carePrefsStoreProvider.overrideWithValue(_MemPrefs()),
        careDocumentStoreProvider.overrideWithValue(sharedDocs),
        careDirectClientProvider.overrideWithValue(direct),
        careRuntimePlatformProvider.overrideWithValue(runtime),
        careVaultPlatformProvider.overrideWithValue(vault),
        careWorkspacePlatformProvider.overrideWithValue(_FakeWorkspace()),
      ],
    );
    await c1.read(careChatProvider.notifier).sendMessage('帮我记住今天跑了 5 公里');
    // Allow async persistence write to settle.
    await Future<void>.delayed(Duration.zero);
    c1.dispose();

    // Cold restart with fresh ProviderContainer reading same local storage.
    final c2 = ProviderContainer(
      overrides: [
        careSecretStoreProvider.overrideWithValue(_MemSecrets()),
        carePrefsStoreProvider.overrideWithValue(_MemPrefs()),
        careDocumentStoreProvider.overrideWithValue(sharedDocs),
        careDirectClientProvider.overrideWithValue(direct),
        careRuntimePlatformProvider.overrideWithValue(runtime),
        careVaultPlatformProvider.overrideWithValue(vault),
        careWorkspacePlatformProvider.overrideWithValue(_FakeWorkspace()),
      ],
    );
    addTearDown(() {
      runtime.dispose();
      c2.dispose();
    });
    await c2.read(careChatProvider.notifier).hydratePersistedThreads();
    final restored = c2.read(careChatProvider);
    expect(restored.messages.length, 2);
    expect(restored.messages.first.content, contains('跑了 5 公里'));
    expect(restored.threadSummaries[kCareChiefBotId]?.lastPreview, contains('隔离处理'));
  });

  test('Chief Bot creates new Bot via bot_create tool and searches 资料库 via knowledge_search', () async {
    final ws = _FakeWorkspace()
      ..files['chief|false|资料库/线代.md'] = '# 线代\n特征值满足 Av = λv';
    final direct = _CapturingDirectClient()..emitBotCreateOnFirstCall = true;
    final runtime = _IdleRuntime();
    final container = ProviderContainer(
      overrides: [
        careSecretStoreProvider.overrideWithValue(_MemSecrets()),
        carePrefsStoreProvider.overrideWithValue(_MemPrefs()),
        careDocumentStoreProvider.overrideWithValue(_MemDocs()),
        careWorkspacePlatformProvider.overrideWithValue(ws),
        careDirectClientProvider.overrideWithValue(direct),
        careRuntimePlatformProvider.overrideWithValue(runtime),
        careVaultPlatformProvider.overrideWithValue(_FakeVault()),
      ],
    );
    addTearDown(() {
      runtime.dispose();
      container.dispose();
    });

    await container.read(careChatProvider.notifier).sendMessage('帮我建一个 Finance Bot');
    final bots = await container.read(careBotsProvider.future);
    expect(bots.specialists.any((b) => b.name == 'Finance'), isTrue);

    // Now test Notebook knowledge_search tool on 资料库/
    direct
      ..callCount = 0
      ..emitBotCreateOnFirstCall = false
      ..emitKnowledgeSearchOnFirstCall = true;
    await container.read(careChatProvider.notifier).sendMessage('特征值的定义是什么');
    final last = container.read(careChatProvider).messages.last;
    expect(
      last.toolActivities.any((a) => a.tool == 'knowledge_search' && a.ok),
      isTrue,
    );
    final sysPrompt = direct.lastMessages!.first['content']! as String;
    expect(sysPrompt, contains('资料库/线代.md'));
  });
}
