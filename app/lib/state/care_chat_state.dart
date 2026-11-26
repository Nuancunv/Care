import 'dart:async';
import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/care_workspace_bridge.dart';
import 'care_automation_state.dart';
import 'care_bots_state.dart';
import 'care_ecosystem_state.dart';
import 'care_memory_state.dart';
import 'care_routine_state.dart';
import 'care_runtime_state.dart';
import 'care_safety_state.dart';
import 'care_schedule_state.dart';
import 'care_settings_state.dart';
import 'care_workspace_state.dart';

const kCareChatHistoryFilename = 'care_chat_history_v1.json';
const _kMaxPersistedMessagesPerBot = 160;

enum CareMessageRole { user, assistant, system }

enum CareChatBackend {
  /// Connected to the on-device PRoot DSH + `care-bot` loopback runtime (127.0.0.1).
  localEngine,

  /// Direct BYOK HTTPS streaming to DeepSeek Official API / custom OpenAI endpoint
  /// with built-in local Agent Workspace, Knowledge Library & Multi-Bot Collaboration Loop.
  directApi,
}

/// Compact record of an Agent tool action performed during an assistant turn.
class CareToolActivity {
  const CareToolActivity({
    required this.tool,
    required this.label,
    this.ok = true,
    this.workspacePath,
  });

  final String tool;
  final String label;
  final bool ok;
  final String? workspacePath;

  Map<String, Object?> toJson() => {
        'tool': tool,
        'label': label,
        'ok': ok,
        if (workspacePath != null) 'workspacePath': workspacePath,
      };

  factory CareToolActivity.fromJson(Map<String, Object?> json) =>
      CareToolActivity(
        tool: json['tool']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        ok: json['ok'] != false,
        workspacePath: json['workspacePath']?.toString(),
      );
}

class CareChatMessage {
  const CareChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.reasoning = '',
    this.attachments = const [],
    this.toolActivities = const [],
  });

  final String id;
  final CareMessageRole role;
  final String content;
  final String reasoning;
  final DateTime createdAt;
  final List<CarePickedAttachment> attachments;
  final List<CareToolActivity> toolActivities;

  Map<String, Object?> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'reasoning': reasoning,
        'createdAtMs': createdAt.millisecondsSinceEpoch,
        'attachments': [
          for (final a in attachments) a.toJson(includePayload: false),
        ],
        'toolActivities': [
          for (final t in toolActivities) t.toJson(),
        ],
      };

  factory CareChatMessage.fromJson(Map<String, Object?> json) {
    final roleStr = json['role']?.toString() ?? 'assistant';
    final role = CareMessageRole.values.firstWhere(
      (r) => r.name == roleStr,
      orElse: () => CareMessageRole.assistant,
    );
    final rawAtt = json['attachments'];
    final rawTools = json['toolActivities'];
    return CareChatMessage(
      id: json['id']?.toString() ?? 'm',
      role: role,
      content: json['content']?.toString() ?? '',
      reasoning: json['reasoning']?.toString() ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAtMs'] as num?)?.toInt() ?? 0,
      ),
      attachments: rawAtt is List
          ? rawAtt
              .whereType<Map>()
              .map(
                (m) => CarePickedAttachment.fromMap(
                  m.map((k, v) => MapEntry(k.toString(), v)),
                ),
              )
              .toList()
          : const [],
      toolActivities: rawTools is List
          ? rawTools
              .whereType<Map>()
              .map(
                (m) => CareToolActivity.fromJson(
                  m.map((k, v) => MapEntry(k.toString(), v)),
                ),
              )
              .toList()
          : const [],
    );
  }
}

/// Lightweight per-Bot thread metadata for the Bot Hub home list.
class CareBotThreadSummary {
  const CareBotThreadSummary({
    required this.lastPreview,
    required this.lastMessageAt,
    this.unread = false,
  });

  final String lastPreview;
  final DateTime lastMessageAt;
  final bool unread;
}

class CareTokenUsage {
  const CareTokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
  });

  final int promptTokens;
  final int completionTokens;

  int get totalTokens => promptTokens + completionTokens;

  CareTokenUsage add({int prompt = 0, int completion = 0}) => CareTokenUsage(
        promptTokens: promptTokens + prompt,
        completionTokens: completionTokens + completion,
      );
}

class CareChatState {
  const CareChatState({
    this.messages = const [],
    this.draftText = '',
    this.draftReasoning = '',
    this.draftToolActivities = const [],
    this.isStreaming = false,
    this.backend = CareChatBackend.directApi,
    this.usage = const CareTokenUsage(),
    this.threadSummaries = const {},
    this.error,
  });

  final List<CareChatMessage> messages;

  /// Streaming incremental reply for the currently active turn.
  /// UI screens should `select` this separately from [messages] to preserve
  /// streaming performance (AGENTS.md §3.1).
  final String draftText;
  final String draftReasoning;
  final List<CareToolActivity> draftToolActivities;
  final bool isStreaming;
  final CareChatBackend backend;
  final CareTokenUsage usage;
  final Map<String, CareBotThreadSummary> threadSummaries;
  final String? error;

  CareChatState copyWith({
    List<CareChatMessage>? messages,
    String? draftText,
    String? draftReasoning,
    List<CareToolActivity>? draftToolActivities,
    bool? isStreaming,
    CareChatBackend? backend,
    CareTokenUsage? usage,
    Map<String, CareBotThreadSummary>? threadSummaries,
    String? error,
    bool clearError = false,
  }) {
    return CareChatState(
      messages: messages ?? this.messages,
      draftText: draftText ?? this.draftText,
      draftReasoning: draftReasoning ?? this.draftReasoning,
      draftToolActivities: draftToolActivities ?? this.draftToolActivities,
      isStreaming: isStreaming ?? this.isStreaming,
      backend: backend ?? this.backend,
      usage: usage ?? this.usage,
      threadSummaries: threadSummaries ?? this.threadSummaries,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Built-in local Agent tools exposed to DeepSeek function calling (zero cloud relay).
const List<Map<String, Object?>> kCareAgentTools = [
  {
    'type': 'function',
    'function': {
      'name': 'workspace_list',
      'description': 'List files currently stored in this Bot\'s local workspace (including 资料库/).',
      'parameters': {'type': 'object', 'properties': <String, Object?>{}},
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'workspace_read',
      'description': 'Read a UTF-8 code, Markdown, or text file from the local workspace or 资料库/.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': 'Relative path inside workspace, e.g. 资料库/笔记.md or index.html'},
        },
        'required': ['path'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'workspace_write',
      'description': 'Create or overwrite a code, Markdown, HTML, JSON, or text file in the local workspace (or under 资料库/).',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': 'Relative file path, e.g. index.html or 资料库/总结.md'},
          'content': {'type': 'string', 'description': 'Full UTF-8 file content'},
        },
        'required': ['path', 'content'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'workspace_delete',
      'description': 'Request deletion of a workspace file (requires native SafetyGate user approval).',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': 'Relative file path to delete'},
        },
        'required': ['path'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'knowledge_list',
      'description': 'List all reference documents inside this Bot\'s 资料库 (Notebook knowledge base).',
      'parameters': {'type': 'object', 'properties': <String, Object?>{}},
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'knowledge_search',
      'description': 'Search this Bot\'s 资料库 (Notebook knowledge base) by keywords and return relevant excerpts with source filenames.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Search keywords or topic to look up in 资料库'},
        },
        'required': ['query'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'bot_list',
      'description': 'List all Bots in the team (excluding locked private vault) with their names, roles, and models.',
      'parameters': {'type': 'object', 'properties': <String, Object?>{}},
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'bot_create',
      'description': 'Create a new specialist Bot in the team when the user asks to create or spawn a Bot (DS-Bot collaboration).',
      'parameters': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': 'Bot name, e.g. Study, Finance, CodeBot'},
          'role': {'type': 'string', 'description': 'Short role description'},
          'system_prompt': {'type': 'string', 'description': 'Custom persona instructions for the new Bot'},
          'avatar_shape': {
            'type': 'string',
            'description': 'One of: acorn, star, moon, wave, kitty, bunny, gumdrop, blossom',
          },
          'avatar_color': {
            'type': 'string',
            'description': 'One of: sky, blue, mint, violet, coral, amber',
          },
          'model': {'type': 'string', 'description': 'Preferred model: deepseek-flash or deepseek-v4-pro'},
          'effort': {'type': 'string', 'description': 'Thinking effort: none, low, high, max'},
        },
        'required': ['name'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'bot_delegate',
      'description': 'Collaborate with another Bot in the team by delegating a sub-question or task to it and returning its response.',
      'parameters': {
        'type': 'object',
        'properties': {
          'bot_name': {'type': 'string', 'description': 'Target Bot name or id, e.g. Study or Finance'},
          'task': {'type': 'string', 'description': 'Clear prompt or question to ask the target Bot'},
        },
        'required': ['bot_name', 'task'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'memory_append',
      'description': 'Save a concise long-term user preference, fact, or habit to local Markdown memory.',
      'parameters': {
        'type': 'object',
        'properties': {
          'entry': {'type': 'string', 'description': 'Concise single-line fact or preference to remember'},
        },
        'required': ['entry'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'calendar_read',
      'description': 'Read upcoming Android system calendar events.',
      'parameters': {'type': 'object', 'properties': <String, Object?>{}},
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'reminder_create',
      'description': 'Create a local Android reminder notification.',
      'parameters': {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': 'Short reminder title'},
          'body': {'type': 'string', 'description': 'Optional detail'},
          'minutes_from_now': {'type': 'integer', 'description': 'Trigger delay in minutes (>= 1)'},
          'repeat_days': {'type': 'integer', 'description': '0 for one-shot, or repeat interval in days'},
        },
        'required': ['title', 'minutes_from_now'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'scheduled_task_create',
      'description': 'Create a recurring local scheduled task (定时任务) when explicitly requested by the user.',
      'parameters': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': 'Short task name, e.g. 晚间待办整理'},
          'description': {'type': 'string', 'description': 'What the task does'},
          'time_hhmm': {'type': 'string', 'description': 'Daily trigger time in HH:mm format, e.g. 21:00'},
          'action': {
            'type': 'string',
            'description': 'Built-in safe action: collect_calendar, collect_notices, collect_memory, or generate_evening_briefing',
          },
        },
        'required': ['name', 'time_hhmm'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'web_fetch',
      'description': 'Fetch readable plain text directly from an HTTPS webpage.',
      'parameters': {
        'type': 'object',
        'properties': {
          'url': {'type': 'string', 'description': 'Target https:// URL'},
        },
        'required': ['url'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'phone_inspect',
      'description': 'Inspect sanitized interactive UI elements on the current Android screen via Accessibility.',
      'parameters': {'type': 'object', 'properties': <String, Object?>{}},
    },
  },
];

/// Single owner of Care's multi-Bot persisted conversation threads (AGENTS.md §3.1).
final careChatProvider = NotifierProvider<CareChatController, CareChatState>(
  CareChatController.new,
);

class CareChatController extends Notifier<CareChatState> {
  StreamSubscription<dynamic>? _activeSub;
  int _seq = 0;
  bool _stopRequested = false;
  Future<void>? _hydrateFuture;
  bool _disposed = false;
  final Map<String, List<CareChatMessage>> _threadsByBot = {};
  final Set<String> _unreadBots = {};
  String _currentBotId = kCareChiefBotId;

  @override
  CareChatState build() {
    _disposed = false;
    _hydrateFuture = null;
    ref.onDispose(() {
      _disposed = true;
      _activeSub?.cancel();
      _activeSub = null;
    });
    Future<void>.microtask(hydratePersistedThreads);
    return const CareChatState();
  }

  /// Loads persisted non-private Bot chat threads from local private app storage.
  Future<void> hydratePersistedThreads() {
    return _hydrateFuture ??= _doHydratePersistedThreads();
  }

  Future<void> _doHydratePersistedThreads() async {
    if (_disposed) return;
    try {
      final raw = await ref
          .read(careDocumentStoreProvider)
          .readDocument(kCareChatHistoryFilename);
      if (_disposed || raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final botId = entry.key.toString();
        // Privacy Bot history is strictly never persisted in shared history (AGENTS.md §1.4).
        if (botId.isEmpty || botId == kCarePrivacyBotId) continue;
        final list = entry.value;
        if (list is! List) continue;
        final parsed = <CareChatMessage>[];
        for (final item in list.whereType<Map>()) {
          parsed.add(
            CareChatMessage.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
            ),
          );
        }
        if (parsed.isNotEmpty) {
          final existing = _threadsByBot[botId];
          if (existing == null || existing.isEmpty) {
            _threadsByBot[botId] = parsed;
          }
        }
      }
      if (_disposed) return;
      final currentMsgs = state.messages.isNotEmpty
          ? state.messages
          : (_threadsByBot[_currentBotId] ?? const <CareChatMessage>[]);
      if (state.messages.isEmpty && currentMsgs.isNotEmpty) {
        _threadsByBot[_currentBotId] = currentMsgs;
      }
      state = state.copyWith(
        messages: currentMsgs,
        threadSummaries: _buildSummaries(currentMessages: currentMsgs),
      );
    } catch (_) {}
  }

  Future<void> _persistThreads() async {
    try {
      _threadsByBot[_currentBotId] = state.messages;
      final payload = <String, Object?>{};
      for (final entry in _threadsByBot.entries) {
        if (entry.key == kCarePrivacyBotId) continue;
        if (entry.value.isEmpty) continue;
        final slice = entry.value.length > _kMaxPersistedMessagesPerBot
            ? entry.value.sublist(
                entry.value.length - _kMaxPersistedMessagesPerBot,
              )
            : entry.value;
        payload[entry.key] = [for (final m in slice) m.toJson()];
      }
      await ref
          .read(careDocumentStoreProvider)
          .writeDocument(kCareChatHistoryFilename, jsonEncode(payload));
    } catch (_) {}
  }

  Map<String, CareBotThreadSummary> _buildSummaries({
    List<CareChatMessage>? currentMessages,
  }) {
    final map = <String, CareBotThreadSummary>{};
    final combined = <String, List<CareChatMessage>>{
      ..._threadsByBot,
      _currentBotId: currentMessages ?? state.messages,
    };
    for (final entry in combined.entries) {
      if (entry.value.isEmpty) continue;
      final last = entry.value.last;
      final clean = last.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      final preview = clean.isNotEmpty
          ? clean
          : (last.toolActivities.isNotEmpty
              ? last.toolActivities.last.label
              : '[附件]');
      map[entry.key] = CareBotThreadSummary(
        lastPreview: preview,
        lastMessageAt: last.createdAt,
        unread: _unreadBots.contains(entry.key),
      );
    }
    return Map.unmodifiable(map);
  }

  void _refreshSummaries() {
    state = state.copyWith(threadSummaries: _buildSummaries());
  }

  void markBotRead(String botId) {
    if (_unreadBots.remove(botId)) {
      _refreshSummaries();
    }
  }

  /// Switches the visible conversation thread to match the active bot (M4).
  /// Preserves strict physical separation between Chief/specialists and Privacy Bot.
  void syncActiveBot(String botId, {CareBotProfile? profile}) {
    _unreadBots.remove(botId);
    if (botId != _currentBotId && !state.isStreaming) {
      _threadsByBot[_currentBotId] = state.messages;
      _currentBotId = botId;
      final nextMessages = _threadsByBot[botId] ?? const <CareChatMessage>[];
      state = state.copyWith(
        messages: nextMessages,
        draftText: '',
        draftReasoning: '',
        draftToolActivities: const [],
        threadSummaries: _buildSummaries(currentMessages: nextMessages),
        clearError: true,
      );
    } else {
      _refreshSummaries();
    }
    if (profile != null && !profile.isChief && !profile.isPrivate) {
      seedSpecialistGreetingIfEmpty(profile, markUnreadIfInactive: false);
    }
  }

  /// Seeds a tailored, warm opening greeting when a new specialist Bot starts
  /// its very first conversation (zero API cost).
  void seedSpecialistGreetingIfEmpty(
    CareBotProfile bot, {
    bool markUnreadIfInactive = true,
  }) {
    if (bot.isChief || bot.isPrivate) return;
    final existing =
        bot.id == _currentBotId ? state.messages : (_threadsByBot[bot.id] ?? const []);
    if (existing.isNotEmpty) return;

    final greeting = CareChatMessage(
      id: _nextId('greet'),
      role: CareMessageRole.assistant,
      content: _buildSpecialistGreeting(bot),
      createdAt: DateTime.now(),
    );
    if (bot.id == _currentBotId) {
      _threadsByBot[bot.id] = [greeting];
      state = state.copyWith(
        messages: [greeting],
        threadSummaries: _buildSummaries(currentMessages: [greeting]),
      );
    } else {
      _threadsByBot[bot.id] = [greeting];
      if (markUnreadIfInactive) _unreadBots.add(bot.id);
      _refreshSummaries();
    }
    unawaited(_persistThreads());
  }

  static String _buildSpecialistGreeting(CareBotProfile bot) {
    final name = bot.name.trim();
    final combined = '${bot.name} ${bot.roleTitle} ${bot.systemPrompt}'.toLowerCase();
    if (combined.contains('study') ||
        combined.contains('学习') ||
        combined.contains('考研') ||
        combined.contains('复习') ||
        combined.contains('备考')) {
      return '你好！我是 $name，你的学习 Bot。今天想攻克哪一科，还是先把课件放进我的「资料库」一起梳理？';
    }
    if (combined.contains('英语') ||
        combined.contains('english') ||
        combined.contains('口语') ||
        combined.contains('翻译')) {
      return 'Hi！我是 $name。今天想练口语对话、润色英文，还是背高频表达？直接发给我吧。';
    }
    if (combined.contains('代码') ||
        combined.contains('编程') ||
        combined.contains('code') ||
        combined.contains('dev')) {
      return '你好！我是 $name。今天在写什么项目，或者有什么需求/报错想一起排查？我可以直接在工作空间帮你写代码。';
    }
    if (combined.contains('finance') ||
        combined.contains('财经') ||
        combined.contains('投资') ||
        combined.contains('理财')) {
      return '你好！我是 $name。今天想看哪块市场动态、财报要点，还是先梳理预算和资产配置？';
    }
    if (combined.contains('行程') ||
        combined.contains('旅行') ||
        combined.contains('旅游') ||
        combined.contains('travel')) {
      return '你好！我是 $name。最近有想去的地方吗？告诉我目的地、天数和预算，我来帮你规划路线和清单。';
    }
    if (combined.contains('阅读') ||
        combined.contains('研究') ||
        combined.contains('读') ||
        combined.contains('书')) {
      return '你好！我是 $name。可以把文章或笔记放进我的「资料库」，或者直接发给我一起拆解。';
    }
    if (combined.contains('健康') ||
        combined.contains('运动') ||
        combined.contains('饮食') ||
        combined.contains('健身') ||
        combined.contains('health')) {
      return '你好！我是 $name。最近作息和状态怎么样？想聊聊运动安排、饮食记录，还是帮你定个小目标？';
    }
    if (bot.roleTitle.trim().isNotEmpty &&
        bot.roleTitle.trim() != '专职 Bot' &&
        bot.roleTitle.trim() != '专职助手') {
      return '你好！我是 $name，负责「${bot.roleTitle.trim()}」。今天有什么想先聊的，或者需要我帮你处理的吗？';
    }
    return '你好！我是 $name。关于 $name 相关的事情，今天想从哪里开始？';
  }

  /// Purges volatile/persisted messages for a bot (e.g. when locking Privacy Bot or deleting a Bot).
  void purgeBotThread(String botId) {
    _threadsByBot.remove(botId);
    _unreadBots.remove(botId);
    if (_currentBotId == botId && !state.isStreaming) {
      _currentBotId = kCareChiefBotId;
      final chiefMsgs = _threadsByBot[kCareChiefBotId] ?? const <CareChatMessage>[];
      state = state.copyWith(
        messages: chiefMsgs,
        draftText: '',
        draftReasoning: '',
        draftToolActivities: const [],
        threadSummaries: _buildSummaries(currentMessages: chiefMsgs),
        clearError: true,
      );
    } else {
      _refreshSummaries();
    }
    if (botId != kCarePrivacyBotId) {
      unawaited(_persistThreads());
    }
  }

  String _nextId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${++_seq}';

  Future<void> sendMessage(
    String rawText, {
    List<CarePickedAttachment> attachments = const [],
  }) async {
    await hydratePersistedThreads();
    final text = rawText.trim();
    if ((text.isEmpty && attachments.isEmpty) || state.isStreaming) return;

    _stopRequested = false;
    final displayContent = text.isNotEmpty
        ? text
        : '请帮我查看并处理这 ${attachments.length} 个附件。';

    final userMsg = CareChatMessage(
      id: _nextId('u'),
      role: CareMessageRole.user,
      content: displayContent,
      attachments: List.unmodifiable(attachments),
      createdAt: DateTime.now(),
    );

    final runtime = ref.read(careRuntimeProvider);
    final useLocalEngine = runtime.isRunning && attachments.isEmpty;
    final nextMessages = [...state.messages, userMsg];
    _threadsByBot[_currentBotId] = nextMessages;

    state = state.copyWith(
      messages: nextMessages,
      draftText: '',
      draftReasoning: '',
      draftToolActivities: const [],
      isStreaming: true,
      backend: useLocalEngine
          ? CareChatBackend.localEngine
          : CareChatBackend.directApi,
      threadSummaries: _buildSummaries(currentMessages: nextMessages),
      clearError: true,
    );
    unawaited(_persistThreads());

    if (useLocalEngine) {
      await _sendViaLocalEngine(runtime, displayContent);
    } else {
      await _sendViaDirectApi();
    }
  }

  Future<void> _sendViaLocalEngine(CareRuntimeState runtime, String text) async {
    DshConnection? conn;
    DsBotHttpTransport? transport;
    try {
      conn = DshConnection(Uri.parse(runtime.baseUrl!));
      await conn.login(runtime.launchToken!);
      transport = DsBotHttpTransport(conn);

      final teamState = await transport.call('state', const {});
      String? mainSessionId;
      if (teamState is Map) {
        final mainBotId = teamState['mainBotId']?.toString();
        final bots = teamState['bots'];
        if (bots is List) {
          for (final b in bots.whereType<Map>()) {
            if (b['id']?.toString() == mainBotId) {
              mainSessionId = b['sessionId']?.toString();
              break;
            }
          }
        }
      }
      if (mainSessionId == null || mainSessionId.isEmpty) {
        throw StateError('Care main bot session not ready in local engine.');
      }

      await transport.call('send', {'sessionId': mainSessionId, 'text': text});

      final buffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      final completer = Completer<void>();

      _activeSub = transport.openFeed().listen(
        (event) {
          final data = event.data;
          if (event.event == 'stream' && data is Map) {
            final sid = data['sessionId']?.toString();
            if (sid != null && sid != mainSessionId) return;
            final delta = data['text']?.toString() ?? '';
            final think = data['reasoning']?.toString() ?? '';
            if (delta.isNotEmpty) buffer.write(delta);
            if (think.isNotEmpty) reasoningBuffer.write(think);
            state = state.copyWith(
              draftText: buffer.toString(),
              draftReasoning: reasoningBuffer.toString(),
            );
          } else if (event.event == 'message' && data is Map) {
            final sid = data['sessionId']?.toString();
            if (sid == mainSessionId && data['role'] == 'assistant') {
              final finalText = data['text']?.toString() ?? buffer.toString();
              _commitAssistantMessage(finalText, reasoningBuffer.toString());
              if (!completer.isCompleted) completer.complete();
            }
          }
        },
        onError: (Object err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
        onDone: () {
          if (!completer.isCompleted) {
            if (buffer.isNotEmpty) {
              _commitAssistantMessage(
                buffer.toString(),
                reasoningBuffer.toString(),
              );
            }
            completer.complete();
          }
        },
      );

      await completer.future.timeout(const Duration(minutes: 3));
    } catch (err) {
      _failTurn(err.toString());
    } finally {
      await _activeSub?.cancel();
      _activeSub = null;
      await transport?.close();
      conn?.close();
    }
  }

  Map<String, Object?> _encodeMessage(CareChatMessage m) {
    final role = m.role == CareMessageRole.user ? 'user' : 'assistant';
    if (m.role != CareMessageRole.user || m.attachments.isEmpty) {
      return {'role': role, 'content': m.content};
    }

    final textBuf = StringBuffer(m.content);
    final imageParts = <Map<String, Object?>>[];
    for (final att in m.attachments) {
      if (att.isImage && att.base64Image.isNotEmpty) {
        imageParts.add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:${att.mimeType};base64,${att.base64Image}',
          },
        });
      } else if (att.textContent.isNotEmpty) {
        textBuf
          ..writeln()
          ..writeln()
          ..writeln('--- 附件文件：${att.name} (${att.mimeType}) ---')
          ..writeln(att.textContent);
      }
    }

    if (imageParts.isEmpty) {
      return {'role': role, 'content': textBuf.toString()};
    }
    return {
      'role': role,
      'content': [
        {'type': 'text', 'text': textBuf.toString()},
        ...imageParts,
      ],
    };
  }

  Future<String> _buildLibraryIndexSection(CareBotProfile bot) async {
    try {
      final files = await ref.read(careWorkspacePlatformProvider).listFiles(
            botId: bot.id,
            isPrivate: bot.isPrivate,
          );
      final libFiles = files.where((f) => f.isInLibrary).toList();
      if (libFiles.isEmpty) return '';
      final listText = libFiles
          .take(30)
          .map((f) => '- ${f.path} (${f.sizeBytes}B)')
          .join('\n');
      return '\n\n## 当前 Bot 资料库（Notebook）\n'
          '以下文件位于你的本地「资料库/」目录中：\n$listText\n'
          '当用户提问涉及上述资料内容时，请优先调用 `knowledge_search` 或 `workspace_read` 查阅原文，严格基于资料回答并注明来源文件名。';
    } catch (_) {
      return '';
    }
  }

  Future<void> _sendViaDirectApi() async {
    try {
      final settings = await ref.read(careSettingsProvider.future);
      final apiKey =
          await ref.read(careSettingsProvider.notifier).readApiKeyForRuntime();
      if (apiKey == null || apiKey.trim().isEmpty) {
        _failTurn('Please configure your DeepSeek API Key first.');
        return;
      }

      final botsState = ref.read(careBotsProvider).value;
      final activeBot = botsState?.activeBot ?? kChiefBotProfile;
      final librarySection = await _buildLibraryIndexSection(activeBot);

      // Privacy Bot isolation (AGENTS.md §1.4): NEVER inject shared MEMORY.md, SOUL.md, or team roster.
      final String systemPrompt;
      const commonToolGuide =
          '\n\n你可以使用本机工具：在工作空间读写代码/网页/文档（workspace_write / workspace_read / workspace_list）、查阅当前 Bot 的「资料库」（knowledge_list / knowledge_search）、记录长期记忆（memory_append）、查看日历（calendar_read）、创建提醒（reminder_create）、按用户需求创建定时任务（scheduled_task_create）或抓取网页（web_fetch）。'
          '当用户让你写 HTML 网页、代码或文档时，先用 workspace_write 保存到工作空间，并在文字回复里清晰总结核心内容（界面会自动展示可渲染预览的文件卡片）。';
      const collabToolGuide =
          '\n你还支持多 Bot 团队协作：当用户让你创建一个新的 Bot（如 Study / Finance / 编程 Bot 等）时，请直接调用 `bot_create` 工具立即创建；当需要其他专职 Bot 协助时，可先用 `bot_list` 查看团队，再用 `bot_delegate` 委托给对应 Bot 并整合它的答复。';

      if (activeBot.isPrivate) {
        if (botsState?.privacyUnlocked != true) {
          _failTurn('Privacy Bot 已锁定，请解锁后再继续对话。');
          return;
        }
        final privateNotes = botsState?.privacyMemoryMarkdown.trim() ?? '';
        systemPrompt = privateNotes.isEmpty
            ? '${activeBot.systemPrompt}$librarySection$commonToolGuide'
            : '${activeBot.systemPrompt}\n\n---\n\n$privateNotes$librarySection$commonToolGuide';
      } else {
        final memory = await ref.read(careMemoryProvider.future);
        final shared =
            '${memory.soulMarkdown.trim()}\n\n---\n\n${memory.memoryMarkdown.trim()}';
        final basePrompt = activeBot.systemPrompt.trim().isEmpty
            ? shared
            : '${activeBot.systemPrompt.trim()}\n\n---\n\n$shared';

        // Detect explicit `@BotName` mentions in the latest user turn to trigger smooth collaboration!
        final latestUserText = state.messages.isNotEmpty &&
                state.messages.last.role == CareMessageRole.user
            ? state.messages.last.content
            : '';
        final mentioned = <String>[];
        if (latestUserText.contains('@') && botsState != null) {
          for (final b in [botsState.chiefBot, ...botsState.specialists]) {
            if (b.id == activeBot.id) continue;
            if (latestUserText.toLowerCase().contains('@${b.name.toLowerCase()}')) {
              mentioned.add(b.name);
            }
          }
        }
        final mentionHint = mentioned.isEmpty
            ? ''
            : '\n\n【点名协作指令】用户在当前消息中显式 @ 了以下 Bot：${mentioned.join('、')}。请优先调用 `bot_delegate` 工具将相关子问题委托给对应 Bot，并把它们的专业答复自然融合到你的回复中。';

        systemPrompt =
            '$basePrompt$librarySection$commonToolGuide$collabToolGuide$mentionHint';
      }

      final effectiveModel =
          activeBot.isChief ? settings.activeModel : activeBot.preferredModel;
      final effectiveEffort =
          activeBot.isChief ? settings.activeEffort : activeBot.preferredEffort;

      final conversation = <Map<String, Object?>>[
        {'role': 'system', 'content': systemPrompt},
        for (final m in state.messages)
          if (m.role != CareMessageRole.system) _encodeMessage(m),
      ];

      final client = ref.read(careDirectClientProvider);
      final textBuf = StringBuffer();
      final reasoningBuf = StringBuffer();
      final activities = <CareToolActivity>[];
      int totalPromptTokens = 0;
      int totalCompletionTokens = 0;

      // Privacy Bot cannot invoke cross-bot collaboration tools (AGENTS.md §1.4).
      final availableTools = activeBot.isPrivate
          ? kCareAgentTools
              .where((t) {
                final fn = t['function'] as Map?;
                final n = fn?['name']?.toString() ?? '';
                return n != 'bot_list' && n != 'bot_create' && n != 'bot_delegate';
              })
              .toList()
          : kCareAgentTools;

      const maxToolRounds = 6;
      for (var round = 0; round < maxToolRounds; round++) {
        if (_stopRequested || !state.isStreaming) break;

        final roundText = StringBuffer();
        final roundToolCalls = <int, _PendingToolCall>{};
        int roundPrompt = 0;
        int roundCompletion = 0;
        final completer = Completer<void>();

        _activeSub = client
            .streamChat(
              apiKey: apiKey,
              model: effectiveModel,
              baseUrl: settings.baseUrl,
              reasoningEffort: effectiveEffort,
              tools: availableTools,
              messages: conversation,
            )
            .listen(
              (chunk) {
                if (chunk.contentDelta.isNotEmpty) {
                  roundText.write(chunk.contentDelta);
                  textBuf.write(chunk.contentDelta);
                }
                if (chunk.reasoningDelta.isNotEmpty) {
                  reasoningBuf.write(chunk.reasoningDelta);
                }
                for (final tc in chunk.toolCallDeltas) {
                  final entry = roundToolCalls.putIfAbsent(
                    tc.index,
                    () => _PendingToolCall(index: tc.index),
                  );
                  if (tc.id != null && tc.id!.isNotEmpty) entry.id = tc.id!;
                  if (tc.name != null && tc.name!.isNotEmpty) {
                    entry.name = tc.name!;
                  }
                  if (tc.argumentsDelta.isNotEmpty) {
                    entry.arguments.write(tc.argumentsDelta);
                  }
                }
                if (chunk.promptTokens != null) {
                  roundPrompt = chunk.promptTokens!;
                }
                if (chunk.completionTokens != null) {
                  roundCompletion = chunk.completionTokens!;
                }
                state = state.copyWith(
                  draftText: textBuf.toString(),
                  draftReasoning: reasoningBuf.toString(),
                  draftToolActivities: List.unmodifiable(activities),
                );
              },
              onError: (Object err) {
                if (!completer.isCompleted) completer.completeError(err);
              },
              onDone: () {
                if (!completer.isCompleted) completer.complete();
              },
              cancelOnError: true,
            );

        await completer.future;
        await _activeSub?.cancel();
        _activeSub = null;

        totalPromptTokens += roundPrompt;
        totalCompletionTokens += roundCompletion;

        if (roundToolCalls.isEmpty || _stopRequested || !state.isStreaming) {
          break;
        }

        final sortedCalls = roundToolCalls.values.toList()
          ..sort((a, b) => a.index.compareTo(b.index));

        conversation.add({
          'role': 'assistant',
          'content': roundText.isEmpty ? null : roundText.toString(),
          'tool_calls': [
            for (final tc in sortedCalls)
              {
                'id': tc.id.isNotEmpty ? tc.id : 'call_${round}_${tc.index}',
                'type': 'function',
                'function': {
                  'name': tc.name,
                  'arguments': tc.arguments.toString(),
                },
              },
          ],
        });

        for (final tc in sortedCalls) {
          final callId =
              tc.id.isNotEmpty ? tc.id : 'call_${round}_${tc.index}';
          final outcome = await _executeAgentTool(
            activeBot: activeBot,
            apiKey: apiKey,
            baseUrl: settings.baseUrl,
            name: tc.name,
            rawArgs: tc.arguments.toString(),
          );
          activities.add(outcome.activity);
          state = state.copyWith(
            draftToolActivities: List.unmodifiable(activities),
          );
          conversation.add({
            'role': 'tool',
            'tool_call_id': callId,
            'content': outcome.toolResult,
          });
        }
      }

      if (state.isStreaming) {
        _commitAssistantMessage(
          textBuf.toString(),
          reasoningBuf.toString(),
          promptTokens: totalPromptTokens,
          completionTokens: totalCompletionTokens,
          toolActivities: activities,
        );
      }
    } catch (err) {
      _failTurn(err.toString());
    } finally {
      await _activeSub?.cancel();
      _activeSub = null;
    }
  }

  Future<_ToolExecutionResult> _executeAgentTool({
    required CareBotProfile activeBot,
    required String apiKey,
    required String baseUrl,
    required String name,
    required String rawArgs,
  }) async {
    Map<String, dynamic> args = const {};
    try {
      final decoded = jsonDecode(rawArgs.isEmpty ? '{}' : rawArgs);
      if (decoded is Map) {
        args = decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}

    try {
      switch (name) {
        case 'workspace_list':
          final files = await ref.read(careWorkspacePlatformProvider).listFiles(
                botId: activeBot.id,
                isPrivate: activeBot.isPrivate,
              );
          final names = files.map((f) => '${f.path} (${f.sizeBytes}B)').toList();
          return _ToolExecutionResult(
            activity: CareToolActivity(
              tool: name,
              label: '已查看工作空间（${files.length} 个文件）',
            ),
            toolResult: jsonEncode({'files': names}),
          );

        case 'workspace_read':
          final path = args['path']?.toString().trim() ?? '';
          final content = await ref.read(careWorkspacePlatformProvider).readFile(
                botId: activeBot.id,
                isPrivate: activeBot.isPrivate,
                path: path,
              );
          return _ToolExecutionResult(
            activity: CareToolActivity(
              tool: name,
              label: content != null ? '已读取：$path' : '未找到：$path',
              ok: content != null,
              workspacePath: content != null ? path : null,
            ),
            toolResult: content ?? 'File not found: $path',
          );

        case 'workspace_write':
          final path = args['path']?.toString().trim() ?? '';
          final content = args['content']?.toString() ?? '';
          final res = await ref.read(careWorkspacePlatformProvider).writeFile(
                botId: activeBot.id,
                isPrivate: activeBot.isPrivate,
                path: path,
                content: content,
              );
          await ref.read(careWorkspaceProvider.notifier).refresh();
          return _ToolExecutionResult(
            activity: CareToolActivity(
              tool: name,
              label: '已写入：$path',
              workspacePath: path,
            ),
            toolResult: jsonEncode(res),
          );

        case 'workspace_delete':
          final path = args['path']?.toString().trim() ?? '';
          // Enforce AGENTS.md §1.3: file deletion MUST pass native SafetyGate approval.
          await ref.read(careSafetyPlatformProvider).evaluateAction(
                action: 'delete_file',
                summary: '删除工作空间文件：$path',
                target: '${activeBot.id}/$path',
              );
          await ref.read(careSafetyProvider.notifier).refresh();
          return _ToolExecutionResult(
            activity: CareToolActivity(
              tool: name,
              label: '删除 $path 需你确认',
              ok: false,
            ),
            toolResult: 'Deletion queued for native SafetyGate user approval.',
          );

        case 'knowledge_list':
          final files = await ref.read(careWorkspacePlatformProvider).listFiles(
                botId: activeBot.id,
                isPrivate: activeBot.isPrivate,
              );
          final lib = files.where((f) => f.isInLibrary).toList();
          return _ToolExecutionResult(
            activity: CareToolActivity(
              tool: name,
              label: '已查看资料库（${lib.length} 份资料）',
            ),
            toolResult: jsonEncode({
              'materials': [
                for (final f in lib) {'path': f.path, 'sizeBytes': f.sizeBytes},
              ],
            }),
          );

        case 'knowledge_search':
          final query = args['query']?.toString().trim() ?? '';
          final hits = await ref.read(careWorkspacePlatformProvider).searchLibrary(
                botId: activeBot.id,
                isPrivate: activeBot.isPrivate,
                query: query,
              );
          return _ToolExecutionResult(
            activity: CareToolActivity(
              tool: name,
              label: hits.isEmpty
                  ? '资料库未命中「$query」'
                  : '已检索资料库（命中 ${hits.length} 处）',
              ok: hits.isNotEmpty,
            ),
            toolResult: jsonEncode({
              'query': query,
              'hits': [
                for (final h in hits) {'source': h.path, 'excerpt': h.snippet},
              ],
            }),
          );

        case 'bot_list':
          if (activeBot.isPrivate) {
            return const _ToolExecutionResult(
              activity: CareToolActivity(
                tool: 'bot_list',
                label: '隐私 Bot 隔离限制',
                ok: false,
              ),
              toolResult: 'Privacy Bot cannot inspect other Bots.',
            );
          }
          final botsState = await ref.read(careBotsProvider.future);
          final roster = [
            botsState.chiefBot,
            ...botsState.specialists,
          ];
          return _ToolExecutionResult(
            activity: CareToolActivity(
              tool: name,
              label: '已查看 Bot 团队（${roster.length} 个）',
            ),
            toolResult: jsonEncode({
              'bots': [
                for (final b in roster)
                  {
                    'id': b.id,
                    'name': b.name,
                    'role': b.roleTitle,
                    'model': b.preferredModel,
                  },
              ],
            }),
          );

        case 'bot_create':
          if (activeBot.isPrivate) {
            return const _ToolExecutionResult(
              activity: CareToolActivity(
                tool: 'bot_create',
                label: '隐私 Bot 无法创建团队 Bot',
                ok: false,
              ),
              toolResult: 'Privacy Bot cannot spawn team Bots.',
            );
          }
          final newName = args['name']?.toString().trim() ?? '';
          if (newName.isEmpty) {
            return const _ToolExecutionResult(
              activity: CareToolActivity(
                tool: 'bot_create',
                label: '缺少 Bot 名称',
                ok: false,
              ),
              toolResult: 'Parameter "name" is required.',
            );
          }
          final role = args['role']?.toString().trim() ?? '';
          final prompt = args['system_prompt']?.toString().trim() ?? '';
          final shape = args['avatar_shape']?.toString().trim() ?? 'star';
          final color = args['avatar_color']?.toString().trim() ?? 'sky';
          final model = args['model']?.toString().trim() ?? kCareDefaultModel;
          final effort = args['effort']?.toString().trim() ?? kCareDefaultEffort;

          final created = await ref.read(careBotsProvider.notifier).spawnSpecialist(
                name: newName,
                roleTitle: role,
                systemPrompt: prompt,
                avatarShape: shape,
                avatarColor: color,
                preferredModel: model,
                preferredEffort: effort,
              );
          seedSpecialistGreetingIfEmpty(created, markUnreadIfInactive: true);
          return _ToolExecutionResult(
            activity: CareToolActivity(
              tool: name,
              label: '已创建新 Bot：${created.name}',
            ),
            toolResult: jsonEncode({
              'created': true,
              'id': created.id,
              'name': created.name,
              'role': created.roleTitle,
              'model': created.preferredModel,
            }),
          );

        case 'bot_delegate':
          if (activeBot.isPrivate) {
            return const _ToolExecutionResult(
              activity: CareToolActivity(
                tool: 'bot_delegate',
                label: '隐私 Bot 禁止对外协作',
                ok: false,
              ),
              toolResult: 'Privacy Bot cannot delegate to other Bots.',
            );
          }
          final targetQuery = args['bot_name']?.toString().trim() ?? '';
          final taskPrompt = args['task']?.toString().trim() ?? '';
          final botsState = await ref.read(careBotsProvider.future);
          final target = botsState.findByNameOrId(targetQuery);
          if (target == null || target.isPrivate || target.id == activeBot.id) {
            return _ToolExecutionResult(
              activity: CareToolActivity(
                tool: name,
                label: '未找到可协作的 Bot：$targetQuery',
                ok: false,
              ),
              toolResult: 'Target Bot "$targetQuery" not found or not eligible for delegation.',
            );
          }
          // Single-hop non-recursive delegation (prevents multi-bot infinite loops, AGENTS.md §3.3).
          final reply = await _runSingleHopDelegation(
            fromBot: activeBot,
            targetBot: target,
            taskPrompt: taskPrompt,
            apiKey: apiKey,
            baseUrl: baseUrl,
          );
          return _ToolExecutionResult(
            activity: CareToolActivity(
              tool: name,
              label: '已与 ${target.name} 协作完成',
            ),
            toolResult: jsonEncode({
              'bot': target.name,
              'reply': reply,
            }),
          );

        case 'memory_append':
          final entry = args['entry']?.toString().trim() ?? '';
          if (entry.isEmpty) {
            return const _ToolExecutionResult(
              activity: CareToolActivity(tool: 'memory_append', label: '记忆内容为空', ok: false),
              toolResult: 'Empty entry.',
            );
          }
          if (activeBot.isPrivate) {
            final cur = ref.read(careBotsProvider).value?.privacyMemoryMarkdown ?? '';
            await ref
                .read(careBotsProvider.notifier)
                .savePrivacyMemory('${cur.trimRight()}\n- $entry\n');
            return const _ToolExecutionResult(
              activity: CareToolActivity(tool: 'memory_append', label: '已记入隐私笔记'),
              toolResult: 'Saved to isolated private memory.',
            );
          } else {
            final mem = await ref.read(careMemoryProvider.future);
            await ref
                .read(careMemoryProvider.notifier)
                .saveMemory('${mem.memoryMarkdown.trimRight()}\n- $entry\n');
            return const _ToolExecutionResult(
              activity: CareToolActivity(tool: 'memory_append', label: '已更新长期记忆'),
              toolResult: 'Saved to MEMORY.md.',
            );
          }

        case 'calendar_read':
          final eco = await ref.read(careEcosystemProvider.future);
          if (!eco.calendarReadGranted) {
            return const _ToolExecutionResult(
              activity: CareToolActivity(tool: 'calendar_read', label: '日历权限未开启', ok: false),
              toolResult: 'Calendar permission is not granted yet.',
            );
          }
          final items = eco.upcomingEvents
              .take(12)
              .map((e) => {
                    'title': e.title,
                    'start': e.start.toIso8601String(),
                    'location': e.location,
                  })
              .toList();
          return _ToolExecutionResult(
            activity: CareToolActivity(
              tool: name,
              label: '已读取日历（${items.length} 条）',
            ),
            toolResult: jsonEncode({'events': items}),
          );

        case 'reminder_create':
          final title = args['title']?.toString().trim() ?? '';
          final body = args['body']?.toString().trim() ?? '';
          final mins = ((args['minutes_from_now'] as num?)?.toInt() ?? 15)
              .clamp(1, 60 * 24 * 365);
          final repeat = (args['repeat_days'] as num?)?.toInt() ?? 0;
          await ref.read(careScheduleProvider.notifier).addReminder(
                title: title.isEmpty ? '提醒' : title,
                body: body,
                triggerAt: DateTime.now().add(Duration(minutes: mins)),
                repeatDays: repeat,
              );
          return _ToolExecutionResult(
            activity: CareToolActivity(
              tool: name,
              label: '已设提醒：$title',
            ),
            toolResult: 'Reminder scheduled in $mins minutes.',
          );

        case 'scheduled_task_create':
          final taskName = args['name']?.toString().trim() ?? '定时任务';
          final desc = args['description']?.toString().trim() ?? '';
          final hhmm = args['time_hhmm']?.toString().trim();
          final action = args['action']?.toString().trim() ?? 'collect_calendar';
          final safeAction = const {
            'collect_calendar',
            'collect_notices',
            'collect_memory',
            'generate_evening_briefing',
          }.contains(action)
              ? action
              : 'collect_calendar';
          await ref.read(careRoutineProvider.notifier).createRoutine(
                name: taskName,
                description: desc,
                scheduleTimeHHmm: (hhmm != null && hhmm.isNotEmpty) ? hhmm : null,
                enabled: true,
                steps: [
                  CareRoutineStep(
                    id: 's1',
                    description: desc.isNotEmpty ? desc : taskName,
                    action: safeAction,
                  ),
                ],
              );
          return _ToolExecutionResult(
            activity: CareToolActivity(
              tool: name,
              label: '已创建定时任务：$taskName${hhmm != null && hhmm.isNotEmpty ? '（$hhmm）' : ''}',
            ),
            toolResult: 'Scheduled task "$taskName" created and enabled.',
          );

        case 'web_fetch':
          final url = args['url']?.toString().trim() ?? '';
          final text = await ref.read(careDirectClientProvider).fetchWebText(url);
          return _ToolExecutionResult(
            activity: CareToolActivity(
              tool: name,
              label: '已读取网页内容',
            ),
            toolResult: text,
          );

        case 'phone_inspect':
          final summary = await ref
              .read(careAutomationProvider.notifier)
              .captureScreenSummary();
          return _ToolExecutionResult(
            activity: CareToolActivity(
              tool: name,
              label: summary.blocked
                  ? '页面受隐私保护拦截'
                  : '已读取屏幕（${summary.nodes.length} 节点）',
              ok: !summary.blocked && summary.available,
            ),
            toolResult: jsonEncode({
              'available': summary.available,
              'blocked': summary.blocked,
              'reason': summary.reason,
              'nodes': summary.nodes
                  .take(30)
                  .map((n) => {'text': n.text, 'clickable': n.clickable})
                  .toList(),
            }),
          );

        default:
          return _ToolExecutionResult(
            activity: CareToolActivity(tool: name, label: '未知工具：$name', ok: false),
            toolResult: 'Unsupported tool: $name',
          );
      }
    } catch (err) {
      return _ToolExecutionResult(
        activity: CareToolActivity(tool: name, label: '工具执行未完成', ok: false),
        toolResult: 'Tool error: $err',
      );
    }
  }

  /// Executes a single-hop, loop-safe delegated request against [targetBot]
  /// using its persona + its own `资料库/` excerpts, and logs the exchange into
  /// [targetBot]'s conversation thread so the user can inspect it directly.
  Future<String> _runSingleHopDelegation({
    required CareBotProfile fromBot,
    required CareBotProfile targetBot,
    required String taskPrompt,
    required String apiKey,
    required String baseUrl,
  }) async {
    final hits = await ref.read(careWorkspacePlatformProvider).searchLibrary(
          botId: targetBot.id,
          isPrivate: false,
          query: taskPrompt,
        );
    final ragContext = hits.isEmpty
        ? ''
        : '\n\n以下是你资料库中的相关参考：\n'
            '${hits.map((h) => '【${h.path}】\n${h.snippet}').join('\n\n')}';

    final sys = '${targetBot.systemPrompt}$ragContext\n\n'
        '你正在与团队中的「${fromBot.name}」协作，请直接给出精炼、准确的答复。';

    final client = ref.read(careDirectClientProvider);
    final buf = StringBuffer();
    await for (final chunk in client.streamChat(
      apiKey: apiKey,
      model: targetBot.preferredModel,
      baseUrl: baseUrl,
      reasoningEffort: targetBot.preferredEffort,
      messages: [
        {'role': 'system', 'content': sys},
        {'role': 'user', 'content': taskPrompt},
      ],
    )) {
      if (chunk.contentDelta.isNotEmpty) buf.write(chunk.contentDelta);
    }

    final reply = buf.toString().trim().isEmpty
        ? '（${targetBot.name} 暂无内容返回）'
        : buf.toString().trim();

    // Record collaboration inside targetBot's own thread + mark unread!
    final targetThread = List<CareChatMessage>.from(
      _threadsByBot[targetBot.id] ?? const <CareChatMessage>[],
    );
    final now = DateTime.now();
    targetThread.add(
      CareChatMessage(
        id: _nextId('collab-u'),
        role: CareMessageRole.user,
        content: '[来自 ${fromBot.name} 的协作请求]\n$taskPrompt',
        createdAt: now,
      ),
    );
    targetThread.add(
      CareChatMessage(
        id: _nextId('collab-a'),
        role: CareMessageRole.assistant,
        content: reply,
        createdAt: now.add(const Duration(milliseconds: 1)),
      ),
    );
    _threadsByBot[targetBot.id] = targetThread;
    _unreadBots.add(targetBot.id);
    _refreshSummaries();
    unawaited(_persistThreads());
    return reply;
  }

  void _commitAssistantMessage(
    String content,
    String reasoning, {
    int promptTokens = 0,
    int completionTokens = 0,
    List<CareToolActivity> toolActivities = const [],
  }) {
    final msg = CareChatMessage(
      id: _nextId('a'),
      role: CareMessageRole.assistant,
      content: content,
      reasoning: reasoning,
      toolActivities: List.unmodifiable(toolActivities),
      createdAt: DateTime.now(),
    );
    final nextMessages = [...state.messages, msg];
    _threadsByBot[_currentBotId] = nextMessages;
    state = state.copyWith(
      messages: nextMessages,
      draftText: '',
      draftReasoning: '',
      draftToolActivities: const [],
      isStreaming: false,
      usage: state.usage.add(
        prompt: promptTokens,
        completion: completionTokens,
      ),
      threadSummaries: _buildSummaries(currentMessages: nextMessages),
      clearError: true,
    );
    unawaited(_persistThreads());
  }

  void _failTurn(String message) {
    state = state.copyWith(
      isStreaming: false,
      draftText: '',
      draftReasoning: '',
      draftToolActivities: const [],
      error: message,
    );
  }

  Future<void> stopStreaming() async {
    _stopRequested = true;
    await _activeSub?.cancel();
    _activeSub = null;
    if (!state.isStreaming) return;
    if (state.draftText.isNotEmpty ||
        state.draftReasoning.isNotEmpty ||
        state.draftToolActivities.isNotEmpty) {
      _commitAssistantMessage(
        state.draftText,
        state.draftReasoning,
        toolActivities: state.draftToolActivities,
      );
    } else {
      state = state.copyWith(
        isStreaming: false,
        draftText: '',
        draftReasoning: '',
        draftToolActivities: const [],
      );
    }
  }

  void clearThread() {
    if (state.isStreaming) return;
    _threadsByBot[_currentBotId] = const [];
    state = state.copyWith(
      messages: const [],
      draftText: '',
      draftReasoning: '',
      draftToolActivities: const [],
      threadSummaries: _buildSummaries(currentMessages: const []),
      clearError: true,
    );
    unawaited(_persistThreads());
  }
}

class _PendingToolCall {
  _PendingToolCall({required this.index});
  final int index;
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}

class _ToolExecutionResult {
  const _ToolExecutionResult({
    required this.activity,
    required this.toolResult,
  });

  final CareToolActivity activity;
  final String toolResult;
}
