import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/care_deepseek_direct.dart';
import 'care_settings_state.dart';

const kCareConnectorsPrefsKey = 'care.connectors.v1';
const kCareMailSecretKey = 'care.mail.app_password';

/// Personal email (IMAP/SMTP) configuration.
/// Password is NEVER stored here — it lives exclusively in Android Keystore (`CareSecretStore`).
class CareMailAccountConfig {
  const CareMailAccountConfig({
    required this.email,
    required this.imapHost,
    this.imapPort = 993,
    required this.smtpHost,
    this.smtpPort = 465,
    this.enabled = true,
    this.hasPassword = false,
  });

  final String email;
  final String imapHost;
  final int imapPort;
  final String smtpHost;
  final int smtpPort;
  final bool enabled;
  final bool hasPassword;

  Map<String, Object?> toJson() => {
        'email': email,
        'imapHost': imapHost,
        'imapPort': imapPort,
        'smtpHost': smtpHost,
        'smtpPort': smtpPort,
        'enabled': enabled,
      };

  factory CareMailAccountConfig.fromJson(
    Map<String, Object?> json, {
    required bool hasPassword,
  }) =>
      CareMailAccountConfig(
        email: json['email']?.toString() ?? '',
        imapHost: json['imapHost']?.toString() ?? '',
        imapPort: (json['imapPort'] as num?)?.toInt() ?? 993,
        smtpHost: json['smtpHost']?.toString() ?? '',
        smtpPort: (json['smtpPort'] as num?)?.toInt() ?? 465,
        enabled: json['enabled'] != false,
        hasPassword: hasPassword,
      );
}

class CareMcpServerConfig {
  const CareMcpServerConfig({
    required this.id,
    required this.name,
    required this.endpointUrl,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String endpointUrl;
  final bool enabled;

  CareMcpServerConfig copyWith({
    String? name,
    String? endpointUrl,
    bool? enabled,
  }) =>
      CareMcpServerConfig(
        id: id,
        name: name ?? this.name,
        endpointUrl: endpointUrl ?? this.endpointUrl,
        enabled: enabled ?? this.enabled,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'endpointUrl': endpointUrl,
        'enabled': enabled,
      };

  factory CareMcpServerConfig.fromJson(Map<String, Object?> json) =>
      CareMcpServerConfig(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        endpointUrl: json['endpointUrl']?.toString() ?? '',
        enabled: json['enabled'] != false,
      );
}

class CareConnectorState {
  const CareConnectorState({
    this.mailAccount,
    this.mcpServers = const [],
  });

  final CareMailAccountConfig? mailAccount;
  final List<CareMcpServerConfig> mcpServers;

  CareConnectorState copyWith({
    CareMailAccountConfig? mailAccount,
    bool clearMail = false,
    List<CareMcpServerConfig>? mcpServers,
  }) =>
      CareConnectorState(
        mailAccount: clearMail ? null : (mailAccount ?? this.mailAccount),
        mcpServers: mcpServers ?? this.mcpServers,
      );
}

/// Single owner of Care's personal connectors (IMAP/SMTP email & MCP Servers — M2).
final careConnectorProvider =
    AsyncNotifierProvider<CareConnectorController, CareConnectorState>(
  CareConnectorController.new,
);

class CareConnectorController extends AsyncNotifier<CareConnectorState> {
  int _seq = 0;

  @override
  Future<CareConnectorState> build() async {
    final prefs = ref.read(carePrefsStoreProvider);
    final secrets = ref.read(careSecretStoreProvider);

    final raw = await prefs.getString(kCareConnectorsPrefsKey);
    final savedPwd = await secrets.read(kCareMailSecretKey);
    final hasPwd = savedPwd != null && savedPwd.isNotEmpty;

    if (raw == null || raw.isEmpty) {
      return const CareConnectorState();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const CareConnectorState();
      CareMailAccountConfig? mail;
      if (decoded['mail'] is Map) {
        mail = CareMailAccountConfig.fromJson(
          (decoded['mail'] as Map).map((k, v) => MapEntry(k.toString(), v)),
          hasPassword: hasPwd,
        );
      }
      final servers = <CareMcpServerConfig>[];
      if (decoded['mcpServers'] is List) {
        for (final item in (decoded['mcpServers'] as List).whereType<Map>()) {
          servers.add(
            CareMcpServerConfig.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
            ),
          );
        }
      }
      return CareConnectorState(mailAccount: mail, mcpServers: servers);
    } catch (_) {
      return const CareConnectorState();
    }
  }

  Future<void> _persist(CareConnectorState next) async {
    final payload = {
      'mail': next.mailAccount?.toJson(),
      'mcpServers': next.mcpServers.map((s) => s.toJson()).toList(),
    };
    await ref
        .read(carePrefsStoreProvider)
        .setString(kCareConnectorsPrefsKey, jsonEncode(payload));
  }

  /// Saves personal IMAP/SMTP settings; app password goes strictly to Android Keystore.
  Future<void> saveMailAccount({
    required String email,
    required String imapHost,
    int imapPort = 993,
    required String smtpHost,
    int smtpPort = 465,
    String? appPassword,
    bool enabled = true,
  }) async {
    final cleanEmail = email.trim();
    if (!cleanEmail.contains('@')) {
      throw const FormatException('Please enter a valid email address.');
    }
    if (imapHost.trim().isEmpty || smtpHost.trim().isEmpty) {
      throw const FormatException('IMAP and SMTP hosts are required.');
    }

    final secrets = ref.read(careSecretStoreProvider);
    if (appPassword != null && appPassword.trim().isNotEmpty) {
      await secrets.write(kCareMailSecretKey, appPassword.trim());
    }
    final pwdNow = await secrets.read(kCareMailSecretKey);

    final current = state.value ?? await future;
    final mail = CareMailAccountConfig(
      email: cleanEmail,
      imapHost: imapHost.trim(),
      imapPort: imapPort,
      smtpHost: smtpHost.trim(),
      smtpPort: smtpPort,
      enabled: enabled,
      hasPassword: pwdNow != null && pwdNow.isNotEmpty,
    );
    final next = current.copyWith(mailAccount: mail);
    await _persist(next);
    state = AsyncData(next);
  }

  Future<void> removeMailAccount() async {
    await ref.read(careSecretStoreProvider).delete(kCareMailSecretKey);
    final current = state.value ?? await future;
    final next = current.copyWith(clearMail: true);
    await _persist(next);
    state = AsyncData(next);
  }

  /// Adds a personal MCP server endpoint (strictly HTTPS or loopback 127.0.0.1).
  Future<CareMcpServerConfig> addMcpServer({
    required String name,
    required String endpointUrl,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const FormatException('MCP server name is required.');
    }
    final validUri = CareDeepSeekDirectClient.validateBaseUrl(endpointUrl);

    final current = state.value ?? await future;
    final server = CareMcpServerConfig(
      id: 'mcp-${DateTime.now().microsecondsSinceEpoch}-${++_seq}',
      name: cleanName,
      endpointUrl: validUri.toString(),
    );
    final next = current.copyWith(mcpServers: [...current.mcpServers, server]);
    await _persist(next);
    state = AsyncData(next);
    return server;
  }

  Future<void> toggleMcpServer(String id, bool enabled) async {
    final current = state.value ?? await future;
    final next = current.copyWith(
      mcpServers: current.mcpServers
          .map((s) => s.id == id ? s.copyWith(enabled: enabled) : s)
          .toList(),
    );
    await _persist(next);
    state = AsyncData(next);
  }

  Future<void> removeMcpServer(String id) async {
    final current = state.value ?? await future;
    final next = current.copyWith(
      mcpServers: current.mcpServers.where((s) => s.id != id).toList(),
    );
    await _persist(next);
    state = AsyncData(next);
  }
}
