import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/care_deepseek_direct.dart';
import '../services/care_storage.dart';

const kCareApiKeyStorageKey = 'care.deepseek_api_key';
const kCareBaseUrlPrefKey = 'care.base_url';
const kCareModelPrefKey = 'care.active_model';
const kCareEffortPrefKey = 'care.active_effort';
const kCareCachedModelsPrefKey = 'care.cached_models.v1';

const kCareDefaultModel = 'deepseek-flash';
const kCareDefaultEffort = 'low';

const kCareLegacyModels = <String>{
  'deepseek-chat',
  'deepseek-reasoner',
};

const kCareDefaultModels = <String>[
  'deepseek-flash',
  'deepseek-v4-pro',
];

class CareSettingsState {
  const CareSettingsState({
    required this.hasApiKey,
    this.maskedApiKey,
    this.baseUrl = CareDeepSeekDirectClient.defaultBaseUrl,
    this.activeModel = kCareDefaultModel,
    this.activeEffort = kCareDefaultEffort,
    this.availableModels = kCareDefaultModels,
    this.isVerifying = false,
    this.connectionVerified = false,
    this.lastError,
  });

  final bool hasApiKey;
  final String? maskedApiKey;
  final String baseUrl;
  final String activeModel;
  final String activeEffort;
  final List<String> availableModels;
  final bool isVerifying;
  final bool connectionVerified;
  final String? lastError;

  CareSettingsState copyWith({
    bool? hasApiKey,
    String? maskedApiKey,
    bool clearMaskedKey = false,
    String? baseUrl,
    String? activeModel,
    String? activeEffort,
    List<String>? availableModels,
    bool? isVerifying,
    bool? connectionVerified,
    String? lastError,
    bool clearError = false,
  }) {
    return CareSettingsState(
      hasApiKey: hasApiKey ?? this.hasApiKey,
      maskedApiKey: clearMaskedKey ? null : (maskedApiKey ?? this.maskedApiKey),
      baseUrl: baseUrl ?? this.baseUrl,
      activeModel: activeModel ?? this.activeModel,
      activeEffort: activeEffort ?? this.activeEffort,
      availableModels: availableModels ?? this.availableModels,
      isVerifying: isVerifying ?? this.isVerifying,
      connectionVerified: connectionVerified ?? this.connectionVerified,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  /// Formats an API key safely for UI display without exposing the secret.
  static String maskKey(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length <= 8) return '••••••••';
    return '${trimmed.substring(0, 5)}••••${trimmed.substring(trimmed.length - 4)}';
  }
}

final careSecretStoreProvider = Provider<CareSecretStore>(
  (ref) => KeystoreSecretStore(),
);

final carePrefsStoreProvider = Provider<CarePrefsStore>(
  (ref) => SharedPrefsStore(),
);

final careDirectClientProvider = Provider<CareDeepSeekDirectClient>((ref) {
  final client = CareDeepSeekDirectClient();
  ref.onDispose(client.close);
  return client;
});

/// Single owner of Care's BYOK DeepSeek API Key & endpoint configuration (AGENTS.md §3.1).
final careSettingsProvider =
    AsyncNotifierProvider<CareSettingsController, CareSettingsState>(
  CareSettingsController.new,
);

class CareSettingsController extends AsyncNotifier<CareSettingsState> {
  @override
  Future<CareSettingsState> build() async {
    final secrets = ref.read(careSecretStoreProvider);
    final prefs = ref.read(carePrefsStoreProvider);

    final key = await secrets.read(kCareApiKeyStorageKey);
    final savedUrl = await prefs.getString(kCareBaseUrlPrefKey);
    final savedModel = await prefs.getString(kCareModelPrefKey);
    final savedEffort = await prefs.getString(kCareEffortPrefKey);
    final savedModelsRaw = await prefs.getString(kCareCachedModelsPrefKey);

    List<String> cachedModels = kCareDefaultModels;
    if (savedModelsRaw != null && savedModelsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(savedModelsRaw);
        if (decoded is List) {
          final parsed = decoded
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty && !kCareLegacyModels.contains(e))
              .toList();
          if (parsed.isNotEmpty) cachedModels = parsed;
        }
      } catch (_) {}
    }

    var effectiveModel = (savedModel != null && savedModel.trim().isNotEmpty)
        ? savedModel.trim()
        : kCareDefaultModel;
    if (effectiveModel == 'deepseek-chat') effectiveModel = 'deepseek-flash';
    if (effectiveModel == 'deepseek-reasoner') {
      effectiveModel = 'deepseek-v4-pro';
    }

    final hasKey = key != null && key.trim().isNotEmpty;
    return CareSettingsState(
      hasApiKey: hasKey,
      maskedApiKey: hasKey ? CareSettingsState.maskKey(key) : null,
      baseUrl: (savedUrl != null && savedUrl.trim().isNotEmpty)
          ? savedUrl.trim()
          : CareDeepSeekDirectClient.defaultBaseUrl,
      activeModel: effectiveModel,
      activeEffort: (savedEffort != null &&
              kCareReasoningEfforts.contains(savedEffort.trim()))
          ? savedEffort.trim()
          : kCareDefaultEffort,
      availableModels: cachedModels,
    );
  }

  /// Validates format and stores the user's DeepSeek API Key in Android Keystore.
  Future<void> saveApiKey(String rawKey) async {
    final key = rawKey.trim();
    if (key.isEmpty || RegExp(r'\s').hasMatch(key)) {
      throw const FormatException('Please enter a valid API Key without spaces.');
    }
    if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(key)) {
      throw const FormatException('Paste only the key value, not a NAME=value line.');
    }
    await ref.read(careSecretStoreProvider).write(kCareApiKeyStorageKey, key);
    final current = state.value ?? const CareSettingsState(hasApiKey: false);
    state = AsyncData(
      current.copyWith(
        hasApiKey: true,
        maskedApiKey: CareSettingsState.maskKey(key),
        connectionVerified: false,
        clearError: true,
      ),
    );
  }

  Future<void> clearApiKey() async {
    await ref.read(careSecretStoreProvider).delete(kCareApiKeyStorageKey);
    final current = state.value ?? const CareSettingsState(hasApiKey: false);
    state = AsyncData(
      current.copyWith(
        hasApiKey: false,
        clearMaskedKey: true,
        connectionVerified: false,
        clearError: true,
      ),
    );
  }

  Future<void> setBaseUrl(String rawUrl) async {
    final uri = CareDeepSeekDirectClient.validateBaseUrl(rawUrl);
    final normalized = uri.toString();
    await ref.read(carePrefsStoreProvider).setString(kCareBaseUrlPrefKey, normalized);
    final current = state.value ?? const CareSettingsState(hasApiKey: false);
    state = AsyncData(
      current.copyWith(
        baseUrl: normalized,
        connectionVerified: false,
        clearError: true,
      ),
    );
  }

  Future<void> setActiveModel(String model) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    await ref.read(carePrefsStoreProvider).setString(kCareModelPrefKey, trimmed);
    final current = state.value ?? const CareSettingsState(hasApiKey: false);
    final merged = {trimmed, ...current.availableModels}.toList();
    state = AsyncData(
      current.copyWith(activeModel: trimmed, availableModels: merged),
    );
  }

  Future<void> setActiveEffort(String effort) async {
    final clean = effort.trim();
    if (!kCareReasoningEfforts.contains(clean)) return;
    await ref.read(carePrefsStoreProvider).setString(kCareEffortPrefKey, clean);
    final current = state.value ?? const CareSettingsState(hasApiKey: false);
    state = AsyncData(current.copyWith(activeEffort: clean));
  }

  /// Directly verifies the saved API Key against `<baseUrl>/models` (zero cloud relay)
  /// and caches all discovered models so future DeepSeek models appear automatically.
  Future<bool> verifyDirectConnection() async {
    final current = state.value ?? await future;
    final key = await ref.read(careSecretStoreProvider).read(kCareApiKeyStorageKey);
    if (key == null || key.trim().isEmpty) {
      state = AsyncData(
        current.copyWith(
          connectionVerified: false,
          lastError: 'API Key is not configured yet.',
        ),
      );
      return false;
    }

    state = AsyncData(current.copyWith(isVerifying: true, clearError: true));
    try {
      final live = await ref.read(careDirectClientProvider).verifyApiKey(
            apiKey: key,
            baseUrl: current.baseUrl,
          );
      final filteredLive =
          live.where((m) => !kCareLegacyModels.contains(m)).toList();
      final merged = filteredLive.isNotEmpty
          ? <String>{...filteredLive, ...kCareDefaultModels}.toList()
          : kCareDefaultModels;
      await ref
          .read(carePrefsStoreProvider)
          .setString(kCareCachedModelsPrefKey, jsonEncode(merged));
      state = AsyncData(
        current.copyWith(
          isVerifying: false,
          connectionVerified: true,
          availableModels: merged,
          clearError: true,
        ),
      );
      return true;
    } catch (err) {
      state = AsyncData(
        current.copyWith(
          isVerifying: false,
          connectionVerified: false,
          lastError: err.toString(),
        ),
      );
      return false;
    }
  }

  /// Internal helper used ONLY by runtime/direct-chat controllers to inject the key in memory.
  /// Never expose this value to UI widgets or logs.
  Future<String?> readApiKeyForRuntime() =>
      ref.read(careSecretStoreProvider).read(kCareApiKeyStorageKey);
}
