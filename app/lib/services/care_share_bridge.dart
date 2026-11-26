import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'care_workspace_bridge.dart';

/// Content shared into Care from another Android app via `ACTION_SEND`.
class CareSharedItem {
  const CareSharedItem({
    required this.kind,
    this.subject = '',
    this.text = '',
    this.fileName = '',
    this.mimeType = 'text/plain',
    this.sizeBytes = 0,
    this.stagedPath = '',
    this.isImage = false,
    this.base64Image = '',
    this.textContent = '',
  });

  final String kind; // 'text', 'image', 'file'
  final String subject;
  final String text;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String stagedPath;
  final bool isImage;
  final String base64Image;
  final String textContent;

  bool get hasFile => stagedPath.isNotEmpty && fileName.isNotEmpty;

  String get displayTitle {
    if (fileName.isNotEmpty) return fileName;
    if (subject.isNotEmpty) return subject;
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length > 40 ? '${clean.substring(0, 40)}…' : clean;
  }

  CarePickedAttachment? toAttachment() {
    if (!hasFile) return null;
    return CarePickedAttachment(
      name: fileName,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      isImage: isImage,
      base64Image: base64Image,
      textContent: textContent,
    );
  }

  factory CareSharedItem.fromMap(Map<Object?, Object?> raw) {
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    return CareSharedItem(
      kind: map['kind']?.toString() ?? 'text',
      subject: map['subject']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      fileName: map['fileName']?.toString() ?? '',
      mimeType: map['mimeType']?.toString() ?? 'text/plain',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      stagedPath: map['stagedPath']?.toString() ?? '',
      isImage: map['isImage'] == true,
      base64Image: map['base64Image']?.toString() ?? '',
      textContent: map['textContent']?.toString() ?? '',
    );
  }
}

abstract class CareSharePlatform {
  Future<CareSharedItem?> takePendingShare();
  Stream<CareSharedItem> shareEvents();
}

class MethodChannelCareSharePlatform implements CareSharePlatform {
  static const _methods = MethodChannel('care/share');
  static const _events = EventChannel('care/share/events');

  @override
  Future<CareSharedItem?> takePendingShare() async {
    try {
      final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
        'takePendingShare',
      );
      if (raw == null) return null;
      return CareSharedItem.fromMap(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<CareSharedItem> shareEvents() => _events
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .map((e) => CareSharedItem.fromMap(e as Map<Object?, Object?>));
}

final careSharePlatformProvider = Provider<CareSharePlatform>(
  (ref) => MethodChannelCareSharePlatform(),
);
