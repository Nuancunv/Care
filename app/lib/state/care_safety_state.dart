import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/care_platform_bridge.dart';

class CareSafetyRequest {
  const CareSafetyRequest({
    required this.id,
    required this.action,
    required this.summary,
    required this.riskLevel,
    required this.createdAtMs,
    this.target,
  });

  factory CareSafetyRequest.fromMap(Map<String, Object?> map) {
    return CareSafetyRequest(
      id: map['id']?.toString() ?? '',
      action: map['action']?.toString() ?? '',
      summary: map['summary']?.toString() ?? '',
      target: map['target']?.toString(),
      riskLevel: map['riskLevel']?.toString() ?? 'L2',
      createdAtMs: (map['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String action;
  final String summary;
  final String? target;
  final String riskLevel;
  final int createdAtMs;
}

class CareSafetyState {
  const CareSafetyState({
    this.pending = const [],
  });

  final List<CareSafetyRequest> pending;

  bool get hasPending => pending.isNotEmpty;
}

final careSafetyPlatformProvider = Provider<CareSafetyPlatform>(
  (ref) => MethodChannelCareSafetyPlatform(),
);

/// Single owner of Care's native SafetyGate approval queue (AGENTS.md §1.3).
final careSafetyProvider =
    NotifierProvider<CareSafetyController, CareSafetyState>(
  CareSafetyController.new,
);

class CareSafetyController extends Notifier<CareSafetyState> {
  StreamSubscription<List<Map<String, Object?>>>? _sub;

  @override
  CareSafetyState build() {
    final platform = ref.read(careSafetyPlatformProvider);
    _sub?.cancel();
    _sub = platform.pendingStream().listen(
      (items) {
        state = CareSafetyState(
          pending: items.map(CareSafetyRequest.fromMap).toList(),
        );
      },
      onError: (_) {},
    );
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
    unawaited(refresh());
    return const CareSafetyState();
  }

  Future<void> refresh() async {
    try {
      final items = await ref.read(careSafetyPlatformProvider).getPending();
      state = CareSafetyState(
        pending: items.map(CareSafetyRequest.fromMap).toList(),
      );
    } catch (_) {}
  }

  Future<bool> approve(String id) async {
    final ok = await ref
        .read(careSafetyPlatformProvider)
        .resolve(id: id, approved: true);
    if (ok) {
      state = CareSafetyState(
        pending: state.pending.where((r) => r.id != id).toList(),
      );
    }
    return ok;
  }

  Future<bool> deny(String id) async {
    final ok = await ref
        .read(careSafetyPlatformProvider)
        .resolve(id: id, approved: false);
    if (ok) {
      state = CareSafetyState(
        pending: state.pending.where((r) => r.id != id).toList(),
      );
    }
    return ok;
  }
}
