import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/care_m3_bridge.dart';
import 'care_safety_state.dart';

class CareAutomationSelfCheck {
  const CareAutomationSelfCheck({
    this.accessibilityEnabled = false,
    this.accessibilityConnected = false,
    this.shizukuInstalled = false,
    this.emergencyStopped = false,
    this.manufacturer = '',
    this.brand = '',
  });

  final bool accessibilityEnabled;
  final bool accessibilityConnected;
  final bool shizukuInstalled;
  final bool emergencyStopped;
  final String manufacturer;
  final String brand;

  bool get ready => accessibilityEnabled && accessibilityConnected && !emergencyStopped;

  factory CareAutomationSelfCheck.fromMap(Map<String, Object?> map) =>
      CareAutomationSelfCheck(
        accessibilityEnabled: map['accessibilityEnabled'] == true,
        accessibilityConnected: map['accessibilityConnected'] == true,
        shizukuInstalled: map['shizukuInstalled'] == true,
        emergencyStopped: map['emergencyStopped'] == true,
        manufacturer: map['manufacturer']?.toString() ?? '',
        brand: map['brand']?.toString() ?? '',
      );
}

class CareScreenNode {
  const CareScreenNode({
    required this.text,
    required this.desc,
    required this.clickable,
    required this.editable,
    required this.sensitive,
  });

  final String text;
  final String desc;
  final bool clickable;
  final bool editable;
  final bool sensitive;

  factory CareScreenNode.fromMap(Map<String, Object?> map) => CareScreenNode(
        text: map['text']?.toString() ?? '',
        desc: map['desc']?.toString() ?? '',
        clickable: map['clickable'] == true,
        editable: map['editable'] == true,
        sensitive: map['sensitive'] == true,
      );
}

class CareScreenSummary {
  const CareScreenSummary({
    required this.available,
    this.blocked = false,
    this.packageName = '',
    this.reason,
    this.nodes = const [],
  });

  final bool available;
  final bool blocked;
  final String packageName;
  final String? reason;
  final List<CareScreenNode> nodes;

  factory CareScreenSummary.fromMap(Map<String, Object?> map) {
    final rawNodes = map['nodes'];
    final parsedNodes = rawNodes is List
        ? rawNodes
            .whereType<Map>()
            .map(
              (m) => CareScreenNode.fromMap(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList()
        : const <CareScreenNode>[];
    return CareScreenSummary(
      available: map['available'] == true,
      blocked: map['blocked'] == true,
      packageName: map['packageName']?.toString() ?? '',
      reason: map['reason']?.toString(),
      nodes: parsedNodes,
    );
  }
}

class CareAutomationState {
  const CareAutomationState({
    this.selfCheck = const CareAutomationSelfCheck(),
    this.lastScreen,
    this.isExecuting = false,
    this.lastOutcome,
    this.lastError,
  });

  final CareAutomationSelfCheck selfCheck;
  final CareScreenSummary? lastScreen;
  final bool isExecuting;
  final String? lastOutcome;
  final String? lastError;

  bool get emergencyStopped => selfCheck.emergencyStopped;

  CareAutomationState copyWith({
    CareAutomationSelfCheck? selfCheck,
    CareScreenSummary? lastScreen,
    bool? isExecuting,
    String? lastOutcome,
    String? lastError,
    bool clearError = false,
  }) =>
      CareAutomationState(
        selfCheck: selfCheck ?? this.selfCheck,
        lastScreen: lastScreen ?? this.lastScreen,
        isExecuting: isExecuting ?? this.isExecuting,
        lastOutcome: lastOutcome ?? this.lastOutcome,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

final careAutomationPlatformProvider = Provider<CareAutomationPlatform>(
  (ref) => MethodChannelCareAutomationPlatform(),
);

/// Single owner of Care's opt-in phone automation status, SafetyGate execution,
/// and emergency-stop takeover controls (M3, AGENTS.md §1.3).
final careAutomationProvider =
    NotifierProvider<CareAutomationController, CareAutomationState>(
  CareAutomationController.new,
);

class CareAutomationController extends Notifier<CareAutomationState> {
  StreamSubscription<Map<String, Object?>>? _sub;

  @override
  CareAutomationState build() {
    final platform = ref.read(careAutomationPlatformProvider);
    _sub?.cancel();
    _sub = platform.events().listen(
      (event) {
        if (event['type'] == 'selfCheck' && event['data'] is Map) {
          final data = (event['data'] as Map)
              .map((k, v) => MapEntry(k.toString(), v));
          state = state.copyWith(
            selfCheck: CareAutomationSelfCheck.fromMap(data),
          );
        }
      },
      onError: (_) {},
    );
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
    unawaited(refreshSelfCheck());
    return const CareAutomationState();
  }

  Future<CareAutomationSelfCheck> refreshSelfCheck() async {
    try {
      final raw = await ref.read(careAutomationPlatformProvider).selfCheck();
      final check = CareAutomationSelfCheck.fromMap(raw);
      state = state.copyWith(selfCheck: check, clearError: true);
      return check;
    } catch (_) {
      return state.selfCheck;
    }
  }

  Future<bool> openAccessibilitySettings() =>
      ref.read(careAutomationPlatformProvider).openAccessibilitySettings();

  Future<CareScreenSummary> captureScreenSummary({int maxNodes = 60}) async {
    final raw = await ref
        .read(careAutomationPlatformProvider)
        .captureScreenSummary(maxNodes: maxNodes);
    final summary = CareScreenSummary.fromMap(raw);
    state = state.copyWith(
      lastScreen: summary,
      lastError: summary.blocked ? summary.reason : null,
      clearError: !summary.blocked,
    );
    return summary;
  }

  /// Submits a high-risk phone action through native Kotlin `SafetyGate` first.
  /// - If L2 approval is required and no [approvalToken] is supplied, enqueues a native
  ///   approval request in `careSafetyProvider` and returns `false` without executing!
  /// - Only executes via Accessibility when a valid single-use native [approvalToken] is passed.
  Future<bool> executeGatedStep({
    required String action,
    required String summary,
    String? targetPackage,
    String? approvalToken,
    String? nodeText,
    double? x,
    double? y,
    String? text,
  }) async {
    if (state.emergencyStopped) {
      state = state.copyWith(
        lastError: 'Emergency stop is active. Clear emergency stop to resume.',
      );
      return false;
    }

    if (approvalToken == null || approvalToken.isEmpty) {
      final gate = await ref.read(careSafetyPlatformProvider).evaluateAction(
            action: action,
            summary: summary,
            target: targetPackage,
          );
      if (gate['requiresApproval'] == true || gate['allowed'] != true) {
        await ref.read(careSafetyProvider.notifier).refresh();
        state = state.copyWith(
          lastOutcome: 'Awaiting native SafetyGate approval: $summary',
          clearError: true,
        );
        return false;
      }
    }

    state = state.copyWith(isExecuting: true, clearError: true);
    try {
      final res = await ref.read(careAutomationPlatformProvider).executeStep(
            action: action,
            approvalToken: approvalToken,
            nodeText: nodeText,
            x: x,
            y: y,
            text: text,
          );
      final ok = res['ok'] == true;
      state = state.copyWith(
        isExecuting: false,
        lastOutcome: ok ? 'Completed: $summary' : null,
        lastError: ok ? null : (res['reason']?.toString() ?? 'Action refused'),
        clearError: ok,
      );
      return ok;
    } catch (err) {
      state = state.copyWith(isExecuting: false, lastError: err.toString());
      return false;
    }
  }

  /// Immediate kill-switch for mid-task user takeover (AGENTS.md §1.3).
  Future<void> emergencyStop() async {
    await ref.read(careAutomationPlatformProvider).emergencyStop();
    await refreshSelfCheck();
    state = state.copyWith(
      isExecuting: false,
      lastOutcome: 'Emergency stop triggered; user took over control.',
      clearError: true,
    );
  }

  Future<void> clearEmergencyStop() async {
    await ref.read(careAutomationPlatformProvider).clearEmergencyStop();
    await refreshSelfCheck();
  }
}
