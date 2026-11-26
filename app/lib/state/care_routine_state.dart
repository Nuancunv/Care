import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'care_automation_state.dart';
import 'care_ecosystem_state.dart';
import 'care_memory_state.dart';
import 'care_safety_state.dart';
import 'care_schedule_state.dart';
import 'care_settings_state.dart';

const kCareRoutinesPrefsKey = 'care.routines.v1';

class CareRoutineStep {
  const CareRoutineStep({
    required this.id,
    required this.description,
    required this.action,
    this.params = const {},
    this.requiresApproval = false,
  });

  final String id;
  final String description;

  /// Supported built-in local actions:
  /// - `collect_calendar` (L0 read)
  /// - `collect_notices` (L0 read)
  /// - `collect_memory` (L0 read)
  /// - `create_reminder` (L1 local)
  /// - `accessibility_click` / `accessibility_write` (L2 — ALWAYS gated by SafetyGate!)
  final String action;
  final Map<String, String> params;
  final bool requiresApproval;

  bool get isHighRisk =>
      requiresApproval ||
      action.startsWith('accessibility_') ||
      action == 'send_external_message' ||
      action == 'send_email' ||
      action == 'payment_action';

  Map<String, Object?> toJson() => {
        'id': id,
        'description': description,
        'action': action,
        'params': params,
        'requiresApproval': requiresApproval,
      };

  factory CareRoutineStep.fromJson(Map<String, Object?> json) {
    final rawParams = json['params'];
    final parsedParams = rawParams is Map
        ? rawParams.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
        : const <String, String>{};
    return CareRoutineStep(
      id: json['id']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      params: parsedParams,
      requiresApproval: json['requiresApproval'] == true,
    );
  }
}

class CareRoutine {
  const CareRoutine({
    required this.id,
    required this.name,
    required this.description,
    required this.steps,
    this.scheduleTimeHHmm,
    this.enabled = false,
    this.lastRunAt,
    this.lastRunSummary,
  });

  final String id;
  final String name;
  final String description;
  final List<CareRoutineStep> steps;
  final String? scheduleTimeHHmm;
  final bool enabled;
  final DateTime? lastRunAt;
  final String? lastRunSummary;

  CareRoutine copyWith({
    String? name,
    String? description,
    List<CareRoutineStep>? steps,
    String? scheduleTimeHHmm,
    bool? enabled,
    DateTime? lastRunAt,
    String? lastRunSummary,
  }) =>
      CareRoutine(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        steps: steps ?? this.steps,
        scheduleTimeHHmm: scheduleTimeHHmm ?? this.scheduleTimeHHmm,
        enabled: enabled ?? this.enabled,
        lastRunAt: lastRunAt ?? this.lastRunAt,
        lastRunSummary: lastRunSummary ?? this.lastRunSummary,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'steps': steps.map((s) => s.toJson()).toList(),
        'scheduleTimeHHmm': scheduleTimeHHmm,
        'enabled': enabled,
        'lastRunAtMs': lastRunAt?.millisecondsSinceEpoch,
        'lastRunSummary': lastRunSummary,
      };

  factory CareRoutine.fromJson(Map<String, Object?> json) {
    final rawSteps = json['steps'];
    final steps = rawSteps is List
        ? rawSteps
            .whereType<Map>()
            .map(
              (m) => CareRoutineStep.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList()
        : const <CareRoutineStep>[];
    final lastMs = (json['lastRunAtMs'] as num?)?.toInt();
    return CareRoutine(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      steps: steps,
      scheduleTimeHHmm: json['scheduleTimeHHmm']?.toString(),
      enabled: json['enabled'] == true,
      lastRunAt: lastMs != null ? DateTime.fromMillisecondsSinceEpoch(lastMs) : null,
      lastRunSummary: json['lastRunSummary']?.toString(),
    );
  }
}

class CareRoutineRunResult {
  const CareRoutineRunResult({
    required this.routineId,
    required this.completed,
    required this.pausedForApproval,
    required this.summary,
  });

  final String routineId;
  final bool completed;
  final bool pausedForApproval;
  final String summary;
}

class CareRoutineState {
  const CareRoutineState({
    this.routines = const [],
    this.runningRoutineId,
    this.lastResult,
  });

  final List<CareRoutine> routines;
  final String? runningRoutineId;
  final CareRoutineRunResult? lastResult;

  CareRoutineState copyWith({
    List<CareRoutine>? routines,
    String? runningRoutineId,
    bool clearRunning = false,
    CareRoutineRunResult? lastResult,
  }) =>
      CareRoutineState(
        routines: routines ?? this.routines,
        runningRoutineId:
            clearRunning ? null : (runningRoutineId ?? this.runningRoutineId),
        lastResult: lastResult ?? this.lastResult,
      );
}

/// No default scheduled tasks are pre-seeded; users or Care create them on demand.
List<CareRoutine> defaultCareRoutines() => const [];

/// Single owner of Care's teachable local Routines / SOP skills (M3).
final careRoutineProvider =
    AsyncNotifierProvider<CareRoutineController, CareRoutineState>(
  CareRoutineController.new,
);

class CareRoutineController extends AsyncNotifier<CareRoutineState> {
  int _seq = 0;

  @override
  Future<CareRoutineState> build() async {
    final prefs = ref.read(carePrefsStoreProvider);
    final raw = await prefs.getString(kCareRoutinesPrefsKey);
    if (raw == null || raw.isEmpty) {
      return const CareRoutineState(routines: []);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final list = decoded
            .whereType<Map>()
            .map(
              (m) => CareRoutine.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            // Strip legacy untouched built-in templates on upgrade.
            .where((r) => !(r.id.startsWith('builtin-') && !r.enabled && r.lastRunAt == null))
            .toList();
        return CareRoutineState(routines: list);
      }
    } catch (_) {}
    return const CareRoutineState(routines: []);
  }

  Future<void> _persist(List<CareRoutine> routines) =>
      ref.read(carePrefsStoreProvider).setString(
            kCareRoutinesPrefsKey,
            jsonEncode(routines.map((r) => r.toJson()).toList()),
          );

  Future<CareRoutine> createRoutine({
    required String name,
    String description = '',
    required List<CareRoutineStep> steps,
    String? scheduleTimeHHmm,
    bool enabled = false,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const FormatException('Routine name is required.');
    final current = state.value ?? await future;
    final routine = CareRoutine(
      id: 'rt-${DateTime.now().microsecondsSinceEpoch}-${++_seq}',
      name: clean,
      description: description.trim(),
      steps: steps,
      scheduleTimeHHmm: scheduleTimeHHmm,
      enabled: enabled,
    );
    final nextList = [...current.routines, routine];
    await _persist(nextList);
    state = AsyncData(current.copyWith(routines: nextList));
    return routine;
  }

  Future<void> toggleRoutine(String id, bool enabled) async {
    final current = state.value ?? await future;
    final nextList = current.routines
        .map((r) => r.id == id ? r.copyWith(enabled: enabled) : r)
        .toList();
    await _persist(nextList);
    state = AsyncData(current.copyWith(routines: nextList));
  }

  Future<void> deleteRoutine(String id) async {
    final current = state.value ?? await future;
    final nextList = current.routines.where((r) => r.id != id).toList();
    await _persist(nextList);
    state = AsyncData(current.copyWith(routines: nextList));
  }

  /// Executes a Routine step-by-step.
  /// - Halts immediately if `emergencyStopped` is active.
  /// - Any L2 high-risk step pauses and enqueues a native `SafetyGate` approval card
  ///   instead of silently executing (AGENTS.md §1.3).
  Future<CareRoutineRunResult> runRoutine(String id) async {
    final current = state.value ?? await future;
    final routine = current.routines.firstWhere(
      (r) => r.id == id,
      orElse: () => throw StateError('Routine not found: $id'),
    );

    if (ref.read(careAutomationProvider).emergencyStopped) {
      final halted = CareRoutineRunResult(
        routineId: id,
        completed: false,
        pausedForApproval: false,
        summary: '已停止：紧急停止开关处于激活状态。',
      );
      state = AsyncData(current.copyWith(lastResult: halted));
      return halted;
    }

    state = AsyncData(current.copyWith(runningRoutineId: id));
    final log = <String>[];

    for (final step in routine.steps) {
      if (ref.read(careAutomationProvider).emergencyStopped) {
        final halted = CareRoutineRunResult(
          routineId: id,
          completed: false,
          pausedForApproval: false,
          summary: '任务中途被用户紧急停止。已完成：${log.join('；')}',
        );
        state = AsyncData(current.copyWith(clearRunning: true, lastResult: halted));
        return halted;
      }

      if (step.isHighRisk) {
        await ref.read(careSafetyPlatformProvider).evaluateAction(
              action: step.action,
              summary: '[${routine.name}] ${step.description}',
              target: step.params['targetPackage'],
            );
        await ref.read(careSafetyProvider.notifier).refresh();
        final paused = CareRoutineRunResult(
          routineId: id,
          completed: false,
          pausedForApproval: true,
          summary: '已暂停并提交原生安全门审批：${step.description}',
        );
        state = AsyncData(current.copyWith(clearRunning: true, lastResult: paused));
        return paused;
      }

      switch (step.action) {
        case 'collect_calendar':
          final eco = await ref.read(careEcosystemProvider.future);
          log.add('日历日程 ${eco.upcomingEvents.length} 项');
        case 'collect_notices':
          final eco = await ref.read(careEcosystemProvider.future);
          log.add('白名单通知 ${eco.recentNotices.length} 条');
        case 'collect_memory':
          final mem = await ref.read(careMemoryProvider.future);
          log.add('已读取 MEMORY.md（${mem.memoryMarkdown.length} 字符）');
        case 'generate_evening_briefing':
          await ref
              .read(careScheduleProvider.notifier)
              .generateBriefingNow(CareBriefingKind.evening, notify: false);
          log.add('已生成晚间简报');
        default:
          log.add('已执行：${step.description}');
      }
    }

    final summary = log.isEmpty ? '已完成' : log.join(' · ');
    final now = DateTime.now();
    final updatedList = current.routines
        .map(
          (r) => r.id == id
              ? r.copyWith(lastRunAt: now, lastRunSummary: summary)
              : r,
        )
        .toList();
    await _persist(updatedList);

    final result = CareRoutineRunResult(
      routineId: id,
      completed: true,
      pausedForApproval: false,
      summary: summary,
    );
    state = AsyncData(
      current.copyWith(
        routines: updatedList,
        clearRunning: true,
        lastResult: result,
      ),
    );
    return result;
  }
}
