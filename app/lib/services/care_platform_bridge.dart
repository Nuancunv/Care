import 'dart:async';

import 'package:flutter/services.dart';

/// Platform bridge to Kotlin `CareRuntimePlugin` (`care/runtime`, `care/runtime/events`).
abstract class CareRuntimePlatform {
  Future<Map<String, Object?>> getStatus();
  Future<void> install();
  Future<void> start(Map<String, String> env);
  Future<void> stop();
  Future<List<String>> getLogs({int lines = 200});
  Future<bool> isBatteryExempt();
  Future<bool> requestBatteryExempt();
  Stream<Map<String, Object?>> events();
}

class MethodChannelCareRuntimePlatform implements CareRuntimePlatform {
  static const _methods = MethodChannel('care/runtime');
  static const _events = EventChannel('care/runtime/events');

  @override
  Future<Map<String, Object?>> getStatus() async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>('getStatus');
    return _castMap(raw);
  }

  @override
  Future<void> install() => _methods.invokeMethod<void>('install');

  @override
  Future<void> start(Map<String, String> env) =>
      _methods.invokeMethod<void>('start', {'env': env});

  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');

  @override
  Future<List<String>> getLogs({int lines = 200}) async {
    final raw = await _methods.invokeMethod<List<Object?>>(
      'getLogs',
      {'lines': lines},
    );
    return raw?.map((e) => e.toString()).toList() ?? const [];
  }

  @override
  Future<bool> isBatteryExempt() async =>
      (await _methods.invokeMethod<bool>('batteryExempt')) ?? false;

  @override
  Future<bool> requestBatteryExempt() async =>
      (await _methods.invokeMethod<bool>('requestBatteryExempt')) ?? false;

  @override
  Stream<Map<String, Object?>> events() =>
      _events.receiveBroadcastStream().map((e) => _castMap(e));

  Map<String, Object?> _castMap(Object? raw) {
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }
}

/// Platform bridge to Kotlin `CareSafetyGatePlugin` (`care/safety`, `care/safety/events`).
abstract class CareSafetyPlatform {
  Future<List<Map<String, Object?>>> getPending();
  Future<Map<String, Object?>> evaluateAction({
    required String action,
    required String summary,
    String? target,
  });
  Future<bool> resolve({required String id, required bool approved});
  Stream<List<Map<String, Object?>>> pendingStream();
}

class MethodChannelCareSafetyPlatform implements CareSafetyPlatform {
  static const _methods = MethodChannel('care/safety');
  static const _events = EventChannel('care/safety/events');

  @override
  Future<List<Map<String, Object?>>> getPending() async {
    final raw = await _methods.invokeMethod<List<Object?>>('getPending');
    return _castList(raw);
  }

  @override
  Future<Map<String, Object?>> evaluateAction({
    required String action,
    required String summary,
    String? target,
  }) async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      'evaluateAction',
      {'action': action, 'summary': summary, 'target': target},
    );
    if (raw == null) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  @override
  Future<bool> resolve({required String id, required bool approved}) async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      'resolve',
      {'id': id, 'approved': approved},
    );
    return raw?['resolved'] == true;
  }

  @override
  Stream<List<Map<String, Object?>>> pendingStream() =>
      _events.receiveBroadcastStream().map((event) {
        if (event is Map && event['items'] is List) {
          return _castList(event['items'] as List<Object?>);
        }
        return const <Map<String, Object?>>[];
      });

  List<Map<String, Object?>> _castList(List<Object?>? raw) {
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }
}
