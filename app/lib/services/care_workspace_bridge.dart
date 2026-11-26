import 'package:flutter/services.dart';

const kCareLibraryFolder = '资料库';

/// Native attachment picked by the user via Android SAF / Gallery / Camera.
class CarePickedAttachment {
  const CarePickedAttachment({
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.isImage,
    this.base64Image = '',
    this.textContent = '',
  });

  final String name;
  final String mimeType;
  final int sizeBytes;
  final bool isImage;
  final String base64Image;
  final String textContent;

  Map<String, Object?> toJson({bool includePayload = false}) => {
        'name': name,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'isImage': isImage,
        if (includePayload) 'base64Image': base64Image,
        if (includePayload) 'textContent': textContent,
      };

  factory CarePickedAttachment.fromMap(Map<String, Object?> map) =>
      CarePickedAttachment(
        name: map['name']?.toString() ?? 'attachment',
        mimeType: map['mimeType']?.toString() ?? 'application/octet-stream',
        sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
        isImage: map['isImage'] == true,
        base64Image: map['base64Image']?.toString() ?? '',
        textContent: map['textContent']?.toString() ?? '',
      );
}

class CareWorkspaceFile {
  const CareWorkspaceFile({
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;

  bool get isInLibrary => path.startsWith('$kCareLibraryFolder/');

  String get displayName =>
      isInLibrary ? path.substring(kCareLibraryFolder.length + 1) : path;

  factory CareWorkspaceFile.fromMap(Map<String, Object?> map) =>
      CareWorkspaceFile(
        path: map['path']?.toString() ?? '',
        sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['modifiedAtMs'] as num?)?.toInt() ?? 0,
        ),
      );
}

class CareLibrarySearchHit {
  const CareLibrarySearchHit({required this.path, required this.snippet});

  final String path;
  final String snippet;

  factory CareLibrarySearchHit.fromMap(Map<String, Object?> map) =>
      CareLibrarySearchHit(
        path: map['path']?.toString() ?? '',
        snippet: map['snippet']?.toString() ?? '',
      );
}

/// Platform bridge to Kotlin `CareWorkspacePlugin` (`care/workspace`).
abstract class CareWorkspacePlatform {
  Future<List<CareWorkspaceFile>> listFiles({
    required String botId,
    required bool isPrivate,
  });

  Future<String?> readFile({
    required String botId,
    required bool isPrivate,
    required String path,
  });

  Future<Map<String, Object?>> writeFile({
    required String botId,
    required bool isPrivate,
    required String path,
    required String content,
  });

  Future<bool> deleteFile({
    required String botId,
    required bool isPrivate,
    required String path,
  });

  /// `mode`: `'file'`, `'camera'`, or `'photo'`
  Future<CarePickedAttachment?> pickAttachment({String mode = 'file'});

  /// Imports any local file straight into `<bot>/资料库/` preserving binary fidelity.
  Future<Map<String, Object?>?> importToLibrary({
    required String botId,
    required bool isPrivate,
  });

  /// Copies a staged Android Share file directly into `<bot>/资料库/`.
  Future<Map<String, Object?>?> importStagedToLibrary({
    required String botId,
    required bool isPrivate,
    required String stagedPath,
    required String fileName,
  });

  /// Keyword search across files stored inside `<bot>/资料库/` (Gemini Notebook style).
  Future<List<CareLibrarySearchHit>> searchLibrary({
    required String botId,
    required bool isPrivate,
    required String query,
  });

  /// Opens a workspace HTML file inside Care's native WebView renderer.
  Future<bool> openHtmlPreview({
    required String botId,
    required bool isPrivate,
    required String path,
  });

  /// Opens a non-private workspace file with the Android system default app via FileProvider.
  Future<bool> openWithExternalApp({
    required String botId,
    required bool isPrivate,
    required String path,
  });
}

class MethodChannelCareWorkspacePlatform implements CareWorkspacePlatform {
  static const _methods = MethodChannel('care/workspace');

  @override
  Future<List<CareWorkspaceFile>> listFiles({
    required String botId,
    required bool isPrivate,
  }) async {
    final raw = await _methods.invokeMethod<List<Object?>>(
      'listFiles',
      {'botId': botId, 'isPrivate': isPrivate},
    );
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map(
          (m) => CareWorkspaceFile.fromMap(
            m.map((k, v) => MapEntry(k.toString(), v)),
          ),
        )
        .toList();
  }

  @override
  Future<String?> readFile({
    required String botId,
    required bool isPrivate,
    required String path,
  }) =>
      _methods.invokeMethod<String>(
        'readFile',
        {'botId': botId, 'isPrivate': isPrivate, 'path': path},
      );

  @override
  Future<Map<String, Object?>> writeFile({
    required String botId,
    required bool isPrivate,
    required String path,
    required String content,
  }) async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      'writeFile',
      {
        'botId': botId,
        'isPrivate': isPrivate,
        'path': path,
        'content': content,
      },
    );
    if (raw == null) return const {'ok': false};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  @override
  Future<bool> deleteFile({
    required String botId,
    required bool isPrivate,
    required String path,
  }) async =>
      (await _methods.invokeMethod<bool>(
        'deleteFile',
        {'botId': botId, 'isPrivate': isPrivate, 'path': path},
      )) ??
      false;

  @override
  Future<CarePickedAttachment?> pickAttachment({String mode = 'file'}) async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      'pickAttachment',
      {'mode': mode},
    );
    if (raw == null) return null;
    return CarePickedAttachment.fromMap(
      raw.map((k, v) => MapEntry(k.toString(), v)),
    );
  }

  @override
  Future<Map<String, Object?>?> importToLibrary({
    required String botId,
    required bool isPrivate,
  }) async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      'importToLibrary',
      {'botId': botId, 'isPrivate': isPrivate},
    );
    if (raw == null) return null;
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  @override
  Future<Map<String, Object?>?> importStagedToLibrary({
    required String botId,
    required bool isPrivate,
    required String stagedPath,
    required String fileName,
  }) async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      'importStagedToLibrary',
      {
        'botId': botId,
        'isPrivate': isPrivate,
        'stagedPath': stagedPath,
        'fileName': fileName,
      },
    );
    if (raw == null) return null;
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  @override
  Future<List<CareLibrarySearchHit>> searchLibrary({
    required String botId,
    required bool isPrivate,
    required String query,
  }) async {
    final raw = await _methods.invokeMethod<List<Object?>>(
      'searchLibrary',
      {'botId': botId, 'isPrivate': isPrivate, 'query': query},
    );
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map(
          (m) => CareLibrarySearchHit.fromMap(
            m.map((k, v) => MapEntry(k.toString(), v)),
          ),
        )
        .toList();
  }

  @override
  Future<bool> openHtmlPreview({
    required String botId,
    required bool isPrivate,
    required String path,
  }) async =>
      (await _methods.invokeMethod<bool>(
        'openHtmlPreview',
        {'botId': botId, 'isPrivate': isPrivate, 'path': path},
      )) ??
      false;

  @override
  Future<bool> openWithExternalApp({
    required String botId,
    required bool isPrivate,
    required String path,
  }) async =>
      (await _methods.invokeMethod<bool>(
        'openWithExternalApp',
        {'botId': botId, 'isPrivate': isPrivate, 'path': path},
      )) ??
      false;
}
