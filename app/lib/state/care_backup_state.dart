import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'care_bots_state.dart';
import 'care_memory_state.dart';
import 'care_routine_state.dart';
import 'care_schedule_state.dart';
import 'care_settings_state.dart';

const kCareBackupPayloadSchema = 'care-backup-payload-v1';

class CareBackupSummary {
  const CareBackupSummary({
    required this.exportedAt,
    required this.routineCount,
    required this.specialistCount,
    required this.includesSecrets,
  });

  final DateTime exportedAt;
  final int routineCount;
  final int specialistCount;

  /// Always `false` — API keys and mailbox passwords never leave Android Keystore (AGENTS.md §1.2).
  final bool includesSecrets;
}

class CareBackupState {
  const CareBackupState({
    this.isBusy = false,
    this.lastEnvelope,
    this.lastSummary,
    this.lastMessage,
    this.lastError,
  });

  final bool isBusy;
  final String? lastEnvelope;
  final CareBackupSummary? lastSummary;
  final String? lastMessage;
  final String? lastError;

  CareBackupState copyWith({
    bool? isBusy,
    String? lastEnvelope,
    CareBackupSummary? lastSummary,
    String? lastMessage,
    String? lastError,
    bool clearError = false,
    bool clearMessage = false,
  }) =>
      CareBackupState(
        isBusy: isBusy ?? this.isBusy,
        lastEnvelope: lastEnvelope ?? this.lastEnvelope,
        lastSummary: lastSummary ?? this.lastSummary,
        lastMessage: clearMessage ? null : (lastMessage ?? this.lastMessage),
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

/// Single owner of Care's zero-cloud local encrypted backup & Markdown export (M4).
final careBackupProvider =
    NotifierProvider<CareBackupController, CareBackupState>(
  CareBackupController.new,
);

class CareBackupController extends Notifier<CareBackupState> {
  @override
  CareBackupState build() => const CareBackupState();

  /// Exports local `SOUL.md`, `MEMORY.md`, briefing config, routines, and non-private
  /// specialist bots into an AES-256-GCM encrypted JSON envelope.
  ///
  /// Strictly excludes API Keys, mailbox passwords, and Privacy Vault documents (AGENTS.md §1.2 & §1.4).
  Future<String> exportEncryptedBackup(String passphrase) async {
    if (passphrase.length < 6) {
      const msg = '加密口令至少需要 6 位字符。';
      state = state.copyWith(lastError: msg, clearMessage: true);
      throw const FormatException(msg);
    }

    state = state.copyWith(isBusy: true, clearError: true, clearMessage: true);
    try {
      final memory = await ref.read(careMemoryProvider.future);
      final schedule = await ref.read(careScheduleProvider.future);
      final routines = await ref.read(careRoutineProvider.future);
      final bots = await ref.read(careBotsProvider.future);
      final now = DateTime.now();

      final payload = <String, Object?>{
        'schema': kCareBackupPayloadSchema,
        'exportedAtMs': now.millisecondsSinceEpoch,
        'soulMarkdown': memory.soulMarkdown,
        'memoryMarkdown': memory.memoryMarkdown,
        'briefingConfig': schedule.config.toJson(),
        'routines': routines.routines.map((r) => r.toJson()).toList(),
        'specialists': bots.specialists.map((b) => b.toJson()).toList(),
      };

      final envelope = await ref.read(careVaultPlatformProvider).encryptBackup(
            passphrase: passphrase,
            payloadJson: jsonEncode(payload),
          );

      final summary = CareBackupSummary(
        exportedAt: now,
        routineCount: routines.routines.length,
        specialistCount: bots.specialists.length,
        includesSecrets: false,
      );

      state = state.copyWith(
        isBusy: false,
        lastEnvelope: envelope,
        lastSummary: summary,
        lastMessage: '已生成本地加密备份（不含 API Key、邮箱授权码与隐私空间）。',
      );
      return envelope;
    } catch (err) {
      state = state.copyWith(isBusy: false, lastError: err.toString());
      rethrow;
    }
  }

  /// Decrypts and restores a local `care-backup-v1` encrypted envelope.
  Future<CareBackupSummary> importEncryptedBackup({
    required String passphrase,
    required String envelopeJson,
  }) async {
    if (passphrase.isEmpty) {
      const msg = '请输入备份口令。';
      state = state.copyWith(lastError: msg, clearMessage: true);
      throw const FormatException(msg);
    }
    final cleanEnvelope = envelopeJson.trim();
    if (cleanEnvelope.isEmpty) {
      const msg = '请粘贴加密备份内容。';
      state = state.copyWith(lastError: msg, clearMessage: true);
      throw const FormatException(msg);
    }

    state = state.copyWith(isBusy: true, clearError: true, clearMessage: true);
    try {
      final plain = await ref.read(careVaultPlatformProvider).decryptBackup(
            passphrase: passphrase,
            envelopeJson: cleanEnvelope,
          );
      final decoded = jsonDecode(plain);
      if (decoded is! Map) {
        throw const FormatException('备份内容结构损坏。');
      }
      final map = decoded.map((k, v) => MapEntry(k.toString(), v));
      if (map['schema'] != kCareBackupPayloadSchema) {
        throw const FormatException('不支持的备份版本。');
      }

      final soul = map['soulMarkdown']?.toString();
      final mem = map['memoryMarkdown']?.toString();
      if (soul != null && soul.isNotEmpty) {
        await ref.read(careMemoryProvider.notifier).saveSoul(soul);
      }
      if (mem != null && mem.isNotEmpty) {
        await ref.read(careMemoryProvider.notifier).saveMemory(mem);
      }

      final rawCfg = map['briefingConfig'];
      if (rawCfg is Map) {
        final cfg = CareBriefingConfig.fromJson(
          rawCfg.map((k, v) => MapEntry(k.toString(), v)),
        );
        await ref.read(careScheduleProvider.notifier).updateConfig(cfg);
      }

      var restoredRoutines = 0;
      final rawRoutines = map['routines'];
      if (rawRoutines is List) {
        final parsed = rawRoutines
            .whereType<Map>()
            .map((m) => CareRoutine.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v))))
            .where((r) => r.id.isNotEmpty && r.name.isNotEmpty)
            .toList();
        if (parsed.isNotEmpty) {
          await ref.read(carePrefsStoreProvider).setString(
                kCareRoutinesPrefsKey,
                jsonEncode(parsed.map((r) => r.toJson()).toList()),
              );
          ref.invalidate(careRoutineProvider);
          restoredRoutines = parsed.length;
        }
      }

      var restoredSpecialists = 0;
      final rawBots = map['specialists'];
      if (rawBots is List) {
        final parsedBots = rawBots
            .whereType<Map>()
            .map((m) => CareBotProfile.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v))))
            .toList();
        await ref
            .read(careBotsProvider.notifier)
            .replaceSpecialistsFromBackup(parsedBots);
        restoredSpecialists = parsedBots.length;
      }

      final summary = CareBackupSummary(
        exportedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['exportedAtMs'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
        routineCount: restoredRoutines,
        specialistCount: restoredSpecialists,
        includesSecrets: false,
      );
      state = state.copyWith(
        isBusy: false,
        lastSummary: summary,
        lastMessage:
            '恢复成功：已导入人格、记忆、$restoredRoutines 个例程与 $restoredSpecialists 位专职助手。',
      );
      return summary;
    } catch (err) {
      state = state.copyWith(isBusy: false, lastError: err.toString());
      rethrow;
    }
  }

  /// Produces a human-readable pure Markdown export of SOUL.md, MEMORY.md, and Routines.
  Future<String> exportPlainMarkdown() async {
    final memory = await ref.read(careMemoryProvider.future);
    final routines = await ref.read(careRoutineProvider.future);
    final buf = StringBuffer()
      ..writeln('# Care 本地记忆与配置导出')
      ..writeln()
      ..writeln('> 导出时间：${DateTime.now().toIso8601String()}')
      ..writeln('> 不含 API Key、邮箱授权码与隐私空间内容。')
      ..writeln()
      ..writeln('---')
      ..writeln()
      ..writeln('## SOUL.md')
      ..writeln()
      ..writeln(memory.soulMarkdown.trim())
      ..writeln()
      ..writeln('---')
      ..writeln()
      ..writeln('## MEMORY.md')
      ..writeln()
      ..writeln(memory.memoryMarkdown.trim())
      ..writeln()
      ..writeln('---')
      ..writeln()
      ..writeln('## 本地例程（Routines）')
      ..writeln();
    for (final r in routines.routines) {
      buf.writeln('- **${r.name}**（${r.steps.length} 步）— ${r.description}');
    }
    return buf.toString();
  }
}
