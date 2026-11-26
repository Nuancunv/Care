import 'dart:async';
import 'dart:convert';

import 'package:care_app/main.dart';
import 'package:care_app/services/care_deepseek_direct.dart';
import 'package:care_app/services/care_platform_bridge.dart';
import 'package:care_app/services/care_storage.dart';
import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemSecretStore implements CareSecretStore {
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

class _FakeRuntimePlatform implements CareRuntimePlatform {
  final _events = StreamController<Map<String, Object?>>.broadcast();
  Map<String, Object?> status = {
    'phase': 'notInstalled',
    'abi': 'arm64-v8a',
    'bundledVersion': 'care-0.1.0',
  };
  Map<String, String>? lastStartedEnv;
  bool installedCalled = false;
  bool stoppedCalled = false;

  @override
  Stream<Map<String, Object?>> events() => _events.stream;

  @override
  Future<List<String>> getLogs({int lines = 200}) async => const [];

  @override
  Future<Map<String, Object?>> getStatus() async => status;

  @override
  Future<void> install() async {
    installedCalled = true;
    status = {...status, 'phase': 'installed', 'installedVersion': 'care-0.1.0'};
    _events.add({'type': 'status', 'status': status});
  }

  @override
  Future<bool> isBatteryExempt() async => true;

  @override
  Future<bool> requestBatteryExempt() async => true;

  @override
  Future<void> start(Map<String, String> env) async {
    lastStartedEnv = env;
    status = {
      ...status,
      'phase': 'running',
      'baseUrl': 'http://127.0.0.1:3080',
      'token': 'tok-test',
    };
    _events.add({'type': 'status', 'status': status});
  }

  @override
  Future<void> stop() async {
    stoppedCalled = true;
    status = {...status, 'phase': 'installed', 'baseUrl': null, 'token': null};
    _events.add({'type': 'status', 'status': status});
  }

  void dispose() => _events.close();
}

class _FakeSafetyPlatform implements CareSafetyPlatform {
  final _stream = StreamController<List<Map<String, Object?>>>.broadcast();
  final List<Map<String, Object?>> items = [
    {
      'id': 'req-1',
      'action': 'payment_action',
      'summary': 'Confirm order checkout',
      'target': 'com.shop.app',
      'riskLevel': 'L2',
      'createdAtMs': 1700000000000,
    },
  ];
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

void main() {
  test('CareDeepSeekDirectClient enforces HTTPS for remote endpoints and allows loopback HTTP', () {
    expect(
      CareDeepSeekDirectClient.validateBaseUrl('https://api.deepseek.com/v1/')
          .toString(),
      'https://api.deepseek.com/v1',
    );
    expect(
      CareDeepSeekDirectClient.validateBaseUrl('http://127.0.0.1:11434/v1')
          .toString(),
      'http://127.0.0.1:11434/v1',
    );
    expect(
      () => CareDeepSeekDirectClient.validateBaseUrl('http://example.com/v1'),
      throwsFormatException,
    );
  });

  test('CareSettingsController stores BYOK key securely, masks display, and verifies directly', () async {
    final secrets = _MemSecretStore();
    final prefs = _MemPrefsStore();
    final mockHttp = MockClient((req) async {
      expect(req.url.toString(), 'https://api.deepseek.com/v1/models');
      expect(req.headers['Authorization'], 'Bearer sk-deepseek-test-987654321');
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 'deepseek-chat'},
            {'id': 'deepseek-reasoner'},
            {'id': 'deepseek-flash'},
            {'id': 'deepseek-v4-pro'},
            {'id': 'deepseek-v5'},
          ],
        }),
        200,
      );
    });

    final container = ProviderContainer(
      overrides: [
        careSecretStoreProvider.overrideWithValue(secrets),
        carePrefsStoreProvider.overrideWithValue(prefs),
        careDirectClientProvider.overrideWithValue(
          CareDeepSeekDirectClient(httpClient: mockHttp),
        ),
      ],
    );
    addTearDown(container.dispose);

    final initial = await container.read(careSettingsProvider.future);
    expect(initial.hasApiKey, isFalse);

    final ctrl = container.read(careSettingsProvider.notifier);
    await expectLater(
      () => ctrl.saveApiKey('DEEPSEEK_API_KEY=sk-bad'),
      throwsFormatException,
    );

    await ctrl.saveApiKey('sk-deepseek-test-987654321');
    final saved = container.read(careSettingsProvider).requireValue;
    expect(saved.hasApiKey, isTrue);
    expect(saved.maskedApiKey, 'sk-de••••4321');
    expect(saved.maskedApiKey!.contains('98765'), isFalse);

    final ok = await ctrl.verifyDirectConnection();
    expect(ok, isTrue);
    final verified = container.read(careSettingsProvider).requireValue;
    expect(verified.connectionVerified, isTrue);
    expect(verified.availableModels, containsAll(['deepseek-flash', 'deepseek-v4-pro', 'deepseek-v5']));
    expect(verified.availableModels, isNot(contains('deepseek-chat')));
    expect(verified.availableModels, isNot(contains('deepseek-reasoner')));
  });

  test('CareMemoryController seeds transparent Markdown SOUL.md and MEMORY.md and persists edits', () async {
    final docs = _MemDocStore();
    final container = ProviderContainer(
      overrides: [
        careDocumentStoreProvider.overrideWithValue(docs),
      ],
    );
    addTearDown(container.dispose);

    final initial = await container.read(careMemoryProvider.future);
    expect(initial.soulMarkdown, contains('Care'));
    expect(initial.memoryMarkdown, contains('MEMORY.md'));

    await container.read(careMemoryProvider.notifier).saveMemory('# MEMORY.md\n- Likes oolong tea');
    final updated = container.read(careMemoryProvider).requireValue;
    expect(updated.memoryMarkdown, contains('oolong tea'));
    expect(await docs.readDocument(kMemoryFilename), contains('oolong tea'));
  });

  test('CareRuntimeController installs offline runtime and injects DEEPSEEK_API_KEY via memory env only', () async {
    final secrets = _MemSecretStore();
    final prefs = _MemPrefsStore();
    final platform = _FakeRuntimePlatform();

    final container = ProviderContainer(
      overrides: [
        careSecretStoreProvider.overrideWithValue(secrets),
        carePrefsStoreProvider.overrideWithValue(prefs),
        careRuntimePlatformProvider.overrideWithValue(platform),
      ],
    );
    addTearDown(() {
      container.dispose();
      platform.dispose();
    });

    final runtimeCtrl = container.read(careRuntimeProvider.notifier);
    await runtimeCtrl.installOfflineRuntime();
    expect(platform.installedCalled, isTrue);

    // Refuses to start when API key is missing
    await runtimeCtrl.startEngine();
    expect(container.read(careRuntimeProvider).phase, CareRuntimePhase.error);
    expect(platform.lastStartedEnv, isNull);

    // After saving BYOK key, injects strictly via process env
    await container.read(careSettingsProvider.notifier).saveApiKey('sk-care-runtime-key-9999');
    await runtimeCtrl.startEngine();
    expect(platform.lastStartedEnv?['DEEPSEEK_API_KEY'], 'sk-care-runtime-key-9999');
    expect(container.read(careRuntimeProvider).isRunning, isTrue);
  });

  test('CareChatController streams direct BYOK replies with reasoning and usage tracking', () async {
    final secrets = _MemSecretStore();
    final prefs = _MemPrefsStore();
    final docs = _MemDocStore();
    final platform = _FakeRuntimePlatform();

    final sseBody = [
      'data: ${jsonEncode({"choices": [{"delta": {"reasoning_content": "Thinking..."}}]})}',
      'data: ${jsonEncode({"choices": [{"delta": {"content": "Hello "}}]})}',
      'data: ${jsonEncode({"choices": [{"delta": {"content": "from Care!"}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 12, "completion_tokens": 4}})}',
      'data: [DONE]',
    ].join('\n');

    final mockHttp = MockClient.streaming((req, bodyStream) async {
      expect(req.url.toString(), 'https://api.deepseek.com/v1/chat/completions');
      return http.StreamedResponse(
        Stream.value(utf8.encode(sseBody)),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });

    final container = ProviderContainer(
      overrides: [
        careSecretStoreProvider.overrideWithValue(secrets),
        carePrefsStoreProvider.overrideWithValue(prefs),
        careDocumentStoreProvider.overrideWithValue(docs),
        careRuntimePlatformProvider.overrideWithValue(platform),
        careDirectClientProvider.overrideWithValue(
          CareDeepSeekDirectClient(httpClient: mockHttp),
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      platform.dispose();
    });

    await container.read(careSettingsProvider.notifier).saveApiKey('sk-chat-test-12345678');
    await container.read(careChatProvider.notifier).sendMessage('Hi Care');

    final chat = container.read(careChatProvider);
    expect(chat.isStreaming, isFalse);
    expect(chat.error, isNull);
    expect(chat.messages.length, 2);
    expect(chat.messages[0].role, CareMessageRole.user);
    expect(chat.messages[1].content, 'Hello from Care!');
    expect(chat.messages[1].reasoning, 'Thinking...');
    expect(chat.usage.totalTokens, 16);
  });

  test('CareSafetyController loads pending L2 requests and resolves approval', () async {
    final safetyPlatform = _FakeSafetyPlatform();
    final container = ProviderContainer(
      overrides: [
        careSafetyPlatformProvider.overrideWithValue(safetyPlatform),
      ],
    );
    addTearDown(() {
      container.dispose();
      safetyPlatform.dispose();
    });

    await container.read(careSafetyProvider.notifier).refresh();
    expect(container.read(careSafetyProvider).pending.length, 1);

    await container.read(careSafetyProvider.notifier).approve('req-1');
    expect(safetyPlatform.lastApproved, isTrue);
    expect(container.read(careSafetyProvider).pending, isEmpty);
  });

  testWidgets('CareApp mounts the Care shell cleanly and routes first run to onboarding', (tester) async {
    final runtime = _FakeRuntimePlatform();
    final safety = _FakeSafetyPlatform()..items.clear();
    addTearDown(() {
      runtime.dispose();
      safety.dispose();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          careSecretStoreProvider.overrideWithValue(_MemSecretStore()),
          carePrefsStoreProvider.overrideWithValue(_MemPrefsStore()),
          careDocumentStoreProvider.overrideWithValue(_MemDocStore()),
          careRuntimePlatformProvider.overrideWithValue(runtime),
          careSafetyPlatformProvider.overrideWithValue(safety),
        ],
        child: const CareApp(),
      ),
    );
    expect(find.byType(Scaffold), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('你好，我是 Care'), findsOneWidget);
  });
}
