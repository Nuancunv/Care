import 'dart:async';

import 'package:flutter/services.dart';

/// Platform bridge to Kotlin `CareAutomationPlugin` (`care/automation`, `care/automation/events`).
abstract class CareAutomationPlatform {
  Future<Map<String, Object?>> selfCheck();
  Future<bool> openAccessibilitySettings();
  Future<Map<String, Object?>> captureScreenSummary({int maxNodes = 60});
  Future<Map<String, Object?>> executeStep({
    required String action,
    required String? approvalToken,
    String? nodeText,
    double? x,
    double? y,
    String? text,
  });
  Future<bool> emergencyStop();
  Future<bool> clearEmergencyStop();
  Stream<Map<String, Object?>> events();
}

class MethodChannelCareAutomationPlatform implements CareAutomationPlatform {
  static const _methods = MethodChannel('care/automation');
  static const _events = EventChannel('care/automation/events');

  @override
  Future<Map<String, Object?>> selfCheck() async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>('selfCheck');
    return _castMap(raw);
  }

  @override
  Future<bool> openAccessibilitySettings() async =>
      (await _methods.invokeMethod<bool>('openAccessibilitySettings')) ?? false;

  @override
  Future<Map<String, Object?>> captureScreenSummary({int maxNodes = 60}) async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      'captureScreenSummary',
      {'maxNodes': maxNodes},
    );
    return _castMap(raw);
  }

  @override
  Future<Map<String, Object?>> executeStep({
    required String action,
    required String? approvalToken,
    String? nodeText,
    double? x,
    double? y,
    String? text,
  }) async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      'executeStep',
      {
        'action': action,
        'approvalToken': approvalToken,
        'nodeText': nodeText,
        'x': x,
        'y': y,
        'text': text,
      },
    );
    return _castMap(raw);
  }

  @override
  Future<bool> emergencyStop() async =>
      (await _methods.invokeMethod<bool>('emergencyStop')) ?? false;

  @override
  Future<bool> clearEmergencyStop() async =>
      (await _methods.invokeMethod<bool>('clearEmergencyStop')) ?? false;

  @override
  Stream<Map<String, Object?>> events() =>
      _events.receiveBroadcastStream().map((e) => _castMap(e));

  Map<String, Object?> _castMap(Object? raw) {
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }
}
