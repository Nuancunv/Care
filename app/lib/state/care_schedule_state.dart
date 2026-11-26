import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/care_m2_bridge.dart';
import 'care_ecosystem_state.dart';
import 'care_memory_state.dart';
import 'care_settings_state.dart';

const kCareSchedulePrefsKey = 'care.schedule_config.v1';

enum CareBriefingKind { morning, evening }

class CareBriefingConfig {
  const CareBriefingConfig({
    this.morningEnabled = false,
    this.morningTime = '08:30',
    this.eveningEnabled = false,
    this.eveningTime = '21:30',
    this.quietStart = '23:00',
    this.quietEnd = '07:30',
    this.idleSleepMinutes = 15,
  });

  final bool morningEnabled;
  final String morningTime;
  final bool eveningEnabled;
  final String eveningTime;
  final String quietStart;
  final String quietEnd;
  final int idleSleepMinutes;

  CareBriefingConfig copyWith({
    bool? morningEnabled,
    String? morningTime,
    bool? eveningEnabled,
    String? eveningTime,
    String? quietStart,
    String? quietEnd,
    int? idleSleepMinutes,
  }) =>
      CareBriefingConfig(
        morningEnabled: morningEnabled ?? this.morningEnabled,
        morningTime: morningTime ?? this.morningTime,
        eveningEnabled: eveningEnabled ?? this.eveningEnabled,
        eveningTime: eveningTime ?? this.eveningTime,
        quietStart: quietStart ?? this.quietStart,
        quietEnd: quietEnd ?? this.quietEnd,
        idleSleepMinutes: idleSleepMinutes ?? this.idleSleepMinutes,
      );

  Map<String, Object?> toJson() => {
        'morningEnabled': morningEnabled,
        'morningTime': morningTime,
        'eveningEnabled': eveningEnabled,
        'eveningTime': eveningTime,
        'quietStart': quietStart,
        'quietEnd': quietEnd,
        'idleSleepMinutes': idleSleepMinutes,
      };

  factory CareBriefingConfig.fromJson(Map<String, Object?> json) =>
      CareBriefingConfig(
        morningEnabled: json['morningEnabled'] == true,
        morningTime: json['morningTime']?.toString() ?? '08:30',
        eveningEnabled: json['eveningEnabled'] == true,
        eveningTime: json['eveningTime']?.toString() ?? '21:30',
        quietStart: json['quietStart']?.toString() ?? '23:00',
        quietEnd: json['quietEnd']?.toString() ?? '07:30',
        idleSleepMinutes: (json['idleSleepMinutes'] as num?)?.toInt() ?? 15,
      );
}

class CareReminderItem {
  const CareReminderItem({
    required this.id,
    required this.title,
    required this.body,
    required this.triggerAt,
    this.repeatDays = 0,
    this.done = false,
  });

  final String id;
  final String title;
  final String body;
  final DateTime triggerAt;
  final int repeatDays;
  final bool done;

  factory CareReminderItem.fromMap(Map<String, Object?> map) => CareReminderItem(
        id: map['id']?.toString() ?? '',
        title: map['title']?.toString() ?? '',
        body: map['body']?.toString() ?? '',
        triggerAt: DateTime.fromMillisecondsSinceEpoch(
          (map['triggerAtMs'] as num?)?.toInt() ?? 0,
        ),
        repeatDays: (map['repeatDays'] as num?)?.toInt() ?? 0,
        done: map['done'] == true,
      );
}

class CareBriefingSnapshot {
  const CareBriefingSnapshot({
    required this.kind,
    required this.title,
    required this.summaryMarkdown,
    required this.generatedAt,
  });

  final CareBriefingKind kind;
  final String title;
  final String summaryMarkdown;
  final DateTime generatedAt;
}

class CareScheduleState {
  const CareScheduleState({
    this.config = const CareBriefingConfig(),
    this.reminders = const [],
    this.latestBriefing,
    this.isGeneratingBriefing = false,
    this.lastError,
  });

  final CareBriefingConfig config;
  final List<CareReminderItem> reminders;
  final CareBriefingSnapshot? latestBriefing;
  final bool isGeneratingBriefing;
  final String? lastError;

  List<CareReminderItem> get activeReminders =>
      reminders.where((r) => !r.done).toList();

  CareScheduleState copyWith({
    CareBriefingConfig? config,
    List<CareReminderItem>? reminders,
    CareBriefingSnapshot? latestBriefing,
    bool? isGeneratingBriefing,
    String? lastError,
    bool clearError = false,
  }) =>
      CareScheduleState(
        config: config ?? this.config,
        reminders: reminders ?? this.reminders,
        latestBriefing: latestBriefing ?? this.latestBriefing,
        isGeneratingBriefing: isGeneratingBriefing ?? this.isGeneratingBriefing,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

final careProactivePlatformProvider = Provider<CareProactivePlatform>(
  (ref) => MethodChannelCareProactivePlatform(),
);

/// Single owner of Care's proactive briefings, quiet hours, idle sleep, and reminders (M2).
final careScheduleProvider =
    AsyncNotifierProvider<CareScheduleController, CareScheduleState>(
  CareScheduleController.new,
);

class CareScheduleController extends AsyncNotifier<CareScheduleState> {
  StreamSubscription<Map<String, Object?>>? _actionSub;
  int _seq = 0;

  @override
  Future<CareScheduleState> build() async {
    final prefs = ref.read(carePrefsStoreProvider);
    final platform = ref.read(careProactivePlatformProvider);

    CareBriefingConfig config = const CareBriefingConfig();
    final raw = await prefs.getString(kCareSchedulePrefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          config = CareBriefingConfig.fromJson(
            decoded.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      } catch (_) {}
    }

    List<CareReminderItem> reminders = const [];
    try {
      final list = await platform.listReminders();
      reminders = list.map(CareReminderItem.fromMap).toList();
    } catch (_) {}

    _actionSub?.cancel();
    _actionSub = platform.actionEvents().listen((event) {
      if (event['type'] == 'notification_action') {
        unawaited(refreshReminders());
      }
    }, onError: (_) {});
    ref.onDispose(() {
      _actionSub?.cancel();
      _actionSub = null;
    });

    return CareScheduleState(config: config, reminders: reminders);
  }

  Future<void> updateConfig(CareBriefingConfig next) async {
    final current = state.value ?? await future;
    await ref
        .read(carePrefsStoreProvider)
        .setString(kCareSchedulePrefsKey, jsonEncode(next.toJson()));

    final platform = ref.read(careProactivePlatformProvider);
    try {
      await platform.scheduleBriefing(
        kind: 'morning',
        enabled: next.morningEnabled,
        time: next.morningTime,
        quietStart: next.quietStart,
        quietEnd: next.quietEnd,
      );
      await platform.scheduleBriefing(
        kind: 'evening',
        enabled: next.eveningEnabled,
        time: next.eveningTime,
        quietStart: next.quietStart,
        quietEnd: next.quietEnd,
      );
      await platform.setIdleSleepMinutes(next.idleSleepMinutes);
    } catch (_) {}

    state = AsyncData(current.copyWith(config: next, clearError: true));
  }

  Future<CareReminderItem> addReminder({
    required String title,
    String body = '',
    required DateTime triggerAt,
    int repeatDays = 0,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Reminder title cannot be empty.');
    }
    final current = state.value ?? await future;
    final id = 'rem-${DateTime.now().microsecondsSinceEpoch}-${++_seq}';
    final platform = ref.read(careProactivePlatformProvider);

    await platform.scheduleReminder(
      id: id,
      title: trimmed,
      body: body.trim(),
      triggerAtMs: triggerAt.millisecondsSinceEpoch,
      repeatDays: repeatDays < 0 ? 0 : repeatDays,
      quietStart: current.config.quietStart,
      quietEnd: current.config.quietEnd,
    );

    final item = CareReminderItem(
      id: id,
      title: trimmed,
      body: body.trim(),
      triggerAt: triggerAt,
      repeatDays: repeatDays < 0 ? 0 : repeatDays,
    );
    state = AsyncData(
      current.copyWith(reminders: [...current.reminders, item], clearError: true),
    );
    return item;
  }

  Future<void> markReminderDone(String id) async {
    final current = state.value ?? await future;
    await ref.read(careProactivePlatformProvider).markReminderDone(id);
    state = AsyncData(
      current.copyWith(
        reminders: current.reminders
            .map(
              (r) => r.id == id
                  ? CareReminderItem(
                      id: r.id,
                      title: r.title,
                      body: r.body,
                      triggerAt: r.triggerAt,
                      repeatDays: r.repeatDays,
                      done: true,
                    )
                  : r,
            )
            .toList(),
      ),
    );
  }

  Future<void> cancelReminder(String id) async {
    final current = state.value ?? await future;
    await ref.read(careProactivePlatformProvider).cancelReminder(id);
    state = AsyncData(
      current.copyWith(
        reminders: current.reminders.where((r) => r.id != id).toList(),
      ),
    );
  }

  Future<void> refreshReminders() async {
    final current = state.value ?? await future;
    try {
      final list = await ref.read(careProactivePlatformProvider).listReminders();
      state = AsyncData(
        current.copyWith(
          reminders: list.map(CareReminderItem.fromMap).toList(),
        ),
      );
    } catch (_) {}
  }

  /// Generates a structured local-first morning/evening briefing from on-device calendar,
  /// active reminders, notice inbox, and `MEMORY.md`, then optionally pushes a native notification.
  Future<CareBriefingSnapshot> generateBriefingNow(
    CareBriefingKind kind, {
    bool notify = true,
  }) async {
    final current = state.value ?? await future;
    state = AsyncData(current.copyWith(isGeneratingBriefing: true, clearError: true));

    final eco = await ref.read(careEcosystemProvider.future);
    final memory = await ref.read(careMemoryProvider.future);

    final title = kind == CareBriefingKind.morning ? 'Care 早间简报' : 'Care 晚间回顾';
    final buf = StringBuffer()..writeln('# $title\n');

    buf.writeln('## 今日日程（本机日历）');
    if (!eco.calendarReadGranted) {
      buf.writeln('- 未开启日历权限（核心功能不受影响，可按需在设置中开启）');
    } else if (eco.upcomingEvents.isEmpty) {
      buf.writeln('- 近期暂无已安排日程');
    } else {
      for (final ev in eco.upcomingEvents.take(5)) {
        final loc = ev.location.isNotEmpty ? ' @ ${ev.location}' : '';
        buf.writeln('- ${ev.title}$loc');
      }
    }

    buf.writeln('\n## 待处理提醒');
    final active = current.activeReminders;
    if (active.isEmpty) {
      buf.writeln('- 当前无待办提醒');
    } else {
      for (final r in active.take(6)) {
        final repeat = r.repeatDays > 0 ? '（每 ${r.repeatDays} 天）' : '';
        buf.writeln('- ${r.title}$repeat${r.body.isNotEmpty ? '：${r.body}' : ''}');
      }
    }

    if (eco.recentNotices.isNotEmpty) {
      buf.writeln('\n## 通知摘要');
      for (final n in eco.recentNotices.take(4)) {
        buf.writeln('- ${n.title}: ${n.text}');
      }
    }

    if (memory.memoryMarkdown.trim().isNotEmpty) {
      buf.writeln('\n## 记忆要点提示');
      buf.writeln('- 已加载本机 `MEMORY.md`（${memory.memoryMarkdown.length} 字符）');
    }

    final snapshot = CareBriefingSnapshot(
      kind: kind,
      title: title,
      summaryMarkdown: buf.toString().trim(),
      generatedAt: DateTime.now(),
    );

    if (notify) {
      try {
        await ref.read(careProactivePlatformProvider).notifyNow(
              id: 'briefing_${kind.name}',
              kind: kind.name,
              title: title,
              body: '日程 ${eco.upcomingEvents.length} 项 · 待办提醒 ${active.length} 项',
            );
      } catch (_) {}
    }

    state = AsyncData(
      current.copyWith(
        latestBriefing: snapshot,
        isGeneratingBriefing: false,
        clearError: true,
      ),
    );
    return snapshot;
  }
}
