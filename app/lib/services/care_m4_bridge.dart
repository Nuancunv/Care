import 'package:flutter/services.dart';

/// Platform bridge to Kotlin `CareBiometricVaultPlugin` (`care/vault`, M4).
///
/// Provides native biometric / device-credential unlock, AES-256-GCM local
/// backup crypto, and physically isolated Privacy Bot file storage.
abstract class CareVaultPlatform {
  Future<Map<String, Object?>> biometricStatus();
  Future<Map<String, Object?>> authenticate({
    required String title,
    required String subtitle,
  });
  Future<String> encryptBackup({
    required String passphrase,
    required String payloadJson,
  });
  Future<String> decryptBackup({
    required String passphrase,
    required String envelopeJson,
  });
  Future<String?> readPrivacyDoc({
    required String botId,
    required String filename,
  });
  Future<bool> writePrivacyDoc({
    required String botId,
    required String filename,
    required String content,
  });
  Future<bool> wipePrivacyVault(String botId);
}

class MethodChannelCareVaultPlatform implements CareVaultPlatform {
  static const _methods = MethodChannel('care/vault');

  @override
  Future<Map<String, Object?>> biometricStatus() async {
    final raw =
        await _methods.invokeMethod<Map<Object?, Object?>>('biometricStatus');
    return _castMap(raw);
  }

  @override
  Future<Map<String, Object?>> authenticate({
    required String title,
    required String subtitle,
  }) async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      'authenticate',
      {'title': title, 'subtitle': subtitle},
    );
    return _castMap(raw);
  }

  @override
  Future<String> encryptBackup({
    required String passphrase,
    required String payloadJson,
  }) async {
    final out = await _methods.invokeMethod<String>(
      'encryptBackup',
      {'passphrase': passphrase, 'payload': payloadJson},
    );
    if (out == null || out.isEmpty) {
      throw StateError('Backup encryption returned empty output.');
    }
    return out;
  }

  @override
  Future<String> decryptBackup({
    required String passphrase,
    required String envelopeJson,
  }) async {
    final out = await _methods.invokeMethod<String>(
      'decryptBackup',
      {'passphrase': passphrase, 'envelope': envelopeJson},
    );
    if (out == null || out.isEmpty) {
      throw StateError('Backup decryption returned empty output.');
    }
    return out;
  }

  @override
  Future<String?> readPrivacyDoc({
    required String botId,
    required String filename,
  }) =>
      _methods.invokeMethod<String>(
        'readPrivacyDoc',
        {'botId': botId, 'filename': filename},
      );

  @override
  Future<bool> writePrivacyDoc({
    required String botId,
    required String filename,
    required String content,
  }) async =>
      (await _methods.invokeMethod<bool>(
        'writePrivacyDoc',
        {'botId': botId, 'filename': filename, 'content': content},
      )) ??
      false;

  @override
  Future<bool> wipePrivacyVault(String botId) async =>
      (await _methods.invokeMethod<bool>(
        'wipePrivacyVault',
        {'botId': botId},
      )) ??
      false;

  Map<String, Object?> _castMap(Object? raw) {
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }
}
