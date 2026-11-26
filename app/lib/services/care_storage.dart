import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Abstraction over encrypted key-value storage (Android Keystore in production).
abstract class CareSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class KeystoreSecretStore implements CareSecretStore {
  KeystoreSecretStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Abstraction over plain user preferences (never used for API keys).
abstract class CarePrefsStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

class SharedPrefsStore implements CarePrefsStore {
  @override
  Future<String?> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

/// Abstraction over Care's local plain-Markdown document store (`SOUL.md`, `MEMORY.md`).
abstract class CareDocumentStore {
  Future<String?> readDocument(String filename);
  Future<void> writeDocument(String filename, String content);
}

class LocalCareDocumentStore implements CareDocumentStore {
  Future<Directory> _careDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}care_data');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<String?> readDocument(String filename) async {
    final dir = await _careDir();
    final file = File('${dir.path}${Platform.pathSeparator}$filename');
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> writeDocument(String filename, String content) async {
    final dir = await _careDir();
    final file = File('${dir.path}${Platform.pathSeparator}$filename');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(file.path);
  }
}
