import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/care_deepseek_direct.dart';
import '../services/care_platform_bridge.dart';
import 'care_settings_state.dart';

enum CareRuntimePhase {
  notBundled,
  notInstalled,
  installing,
  installed,
  starting,
  running,
  stopping,
  error;

  static CareRuntimePhase fromWire(String? wire) {
    return switch (wire) {
      'notBundled' => CareRuntimePhase.notBundled,
      'notInstalled' => CareRuntimePhase.notInstalled,
      'installing' => CareRuntimePhase.installing,
      'installed' => CareRuntimePhase.installed,
      'starting' => CareRuntimePhase.starting,
      'running' => CareRuntimePhase.running,
      'stopping' => CareRuntimePhase.stopping,
      'error' => CareRuntimePhase.error,
      _ => CareRuntimePhase.notBundled,
    };
  }
}

class CareRuntimeState {
  const CareRuntimeState({
    this.phase = CareRuntimePhase.notBundled,
    this.abi = 'arm64-v8a',
    this.bundledVersion,
    this.installedVersion,
    this.dshVersion,
    this.nodeVersion,
    this.baseUrl,
    this.launchToken,
    this.installBytesRead = 0,
    this.installBytesTotal = 0,
    this.error,
    this.recentLogs = const [],
  });

  final CareRuntimePhase phase;
  final String abi;
  final String? bundledVersion;
  final String? installedVersion;
  final String? dshVersion;
  final String? nodeVersion;
  final String? baseUrl;
  final String? launchToken;
  final int installBytesRead;
  final int installBytesTotal;
  final String? error;
  final List<String> recentLogs;

  bool get isRunning =>
      phase == CareRuntimePhase.running &&
      baseUrl != null &&
      launchToken != null;

  double get installProgress =>
      installBytesTotal > 0
          ? (installBytesRead / installBytesTotal).clamp(0.0, 1.0)
          : 0.0;

  CareRuntimeState copyWith({
    CareRuntimePhase? phase,
    String? abi,
    String? bundledVersion,
    String? installedVersion,
    String? dshVersion,
    String? nodeVersion,
    String? baseUrl,
    bool clearConnection = false,
    String? launchToken,
    int? installBytesRead,
    int? installBytesTotal,
    String? error,
    bool clearError = false,
    List<String>? recentLogs,
  }) {
    return CareRuntimeState(
      phase: phase ?? this.phase,
      abi: abi ?? this.abi,
      bundledVersion: bundledVersion ?? this.bundledVersion,
      installedVersion: installedVersion ?? this.installedVersion,
      dshVersion: dshVersion ?? this.dshVersion,
      nodeVersion: nodeVersion ?? this.nodeVersion,
      baseUrl: clearConnection ? null : (baseUrl ?? this.baseUrl),
      launchToken: clearConnection ? null : (launchToken ?? this.launchToken),
      installBytesRead: installBytesRead ?? this.installBytesRead,
      installBytesTotal: installBytesTotal ?? this.installBytesTotal,
      error: clearError ? null : (error ?? this.error),
      recentLogs: recentLogs ?? this.recentLogs,
    );
  }

  factory CareRuntimeState.fromStatusMap(
    Map<String, Object?> map, {
    List<String> recentLogs = const [],
  }) {
    return CareRuntimeState(
      phase: CareRuntimePhase.fromWire(map['phase']?.toString()),
      abi: map['abi']?.toString() ?? 'arm64-v8a',
      bundledVersion: map['bundledVersion']?.toString(),
      installedVersion: map['installedVersion']?.toString(),
      dshVersion: map['dshVersion']?.toString(),
      nodeVersion: map['nodeVersion']?.toString(),
      baseUrl: map['baseUrl']?.toString(),
      launchToken: map['token']?.toString(),
      installBytesRead: (map['installBytesRead'] as num?)?.toInt() ?? 0,
      installBytesTotal: (map['installBytesTotal'] as num?)?.toInt() ?? 0,
      error: map['error']?.toString(),
      recentLogs: recentLogs,
    );
  }
}

final careRuntimePlatformProvider = Provider<CareRuntimePlatform>(
  (ref) => MethodChannelCareRuntimePlatform(),
);

/// Mirrors Kotlin `CareRuntimeController` (the single source of truth — AGENTS.md §3.2).
final careRuntimeProvider =
    NotifierProvider<CareRuntimeController, CareRuntimeState>(
  CareRuntimeController.new,
);

class CareRuntimeController extends Notifier<CareRuntimeState> {
  StreamSubscription<Map<String, Object?>>? _sub;

  @override
  CareRuntimeState build() {
    final platform = ref.read(careRuntimePlatformProvider);
    _sub?.cancel();
    _sub = platform.events().listen(
      _onEvent,
      onError: (_) {
        // Non-Android / unit-test environments without platform channels stay idle cleanly.
      },
    );
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
    unawaited(refreshStatus());
    return const CareRuntimeState();
  }

  void _onEvent(Map<String, Object?> event) {
    final type = event['type']?.toString();
    if (type == 'status' && event['status'] is Map) {
      final statusMap = (event['status'] as Map)
          .map((k, v) => MapEntry(k.toString(), v));
      state = CareRuntimeState.fromStatusMap(
        statusMap,
        recentLogs: state.recentLogs,
      );
    } else if (type == 'log' && event['line'] is String) {
      final next = [...state.recentLogs, event['line'] as String];
      if (next.length > 200) next.removeRange(0, next.length - 200);
      state = state.copyWith(recentLogs: next);
    }
  }

  Future<void> refreshStatus() async {
    try {
      final status = await ref.read(careRuntimePlatformProvider).getStatus();
      state = CareRuntimeState.fromStatusMap(
        status,
        recentLogs: state.recentLogs,
      );
    } catch (_) {
      // Keep default state on non-Android hosts.
    }
  }

  /// Unpacks the offline all-in-one ARM64 runtime bundled in the APK (zero network).
  Future<void> installOfflineRuntime() async {
    await ref.read(careRuntimePlatformProvider).install();
    await refreshStatus();
  }

  /// Starts the local PRoot DSH + `care-bot` engine, injecting `DEEPSEEK_API_KEY`
  /// exclusively through in-memory process environment variables (AGENTS.md §1.2).
  Future<void> startEngine() async {
    final settingsCtrl = ref.read(careSettingsProvider.notifier);
    final settings = await ref.read(careSettingsProvider.future);
    final apiKey = await settingsCtrl.readApiKeyForRuntime();
    if (apiKey == null || apiKey.trim().isEmpty) {
      state = state.copyWith(
        phase: CareRuntimePhase.error,
        error: 'Configure your DeepSeek API Key before starting the local engine.',
      );
      return;
    }

    final env = <String, String>{
      'DEEPSEEK_API_KEY': apiKey.trim(),
      if (settings.baseUrl != CareDeepSeekDirectClient.defaultBaseUrl)
        'DEEPSEEK_BASE_URL': settings.baseUrl,
    };
    await ref.read(careRuntimePlatformProvider).start(env);
  }

  Future<void> stopEngine() async {
    await ref.read(careRuntimePlatformProvider).stop();
  }

  Future<bool> isBatteryExempt() =>
      ref.read(careRuntimePlatformProvider).isBatteryExempt();

  Future<bool> requestBatteryExempt() =>
      ref.read(careRuntimePlatformProvider).requestBatteryExempt();
}
