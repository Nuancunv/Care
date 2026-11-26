import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/care_deepseek_direct.dart';
import '../services/care_m4_bridge.dart';
import 'care_safety_state.dart';
import 'care_settings_state.dart';

const kCareBotsPrefsKey = 'care.bots.roster.v1';
const kCareCoreBotOverridesPrefsKey = 'care.bots.core_overrides.v1';
const kCareChiefBotId = 'chief';
const kCarePrivacyBotId = 'privacy-vault';
const kCarePrivacyMemoryFile = 'PRIVATE_MEMORY.md';

/// Anti-loop ceiling for Chief-routed multi-bot delegation (AGENTS.md §3.3).
const kCareMaxMultiBotHops = 3;

const kDefaultPrivacyMemoryMarkdown = '''# Privacy Bot 笔记（物理隔离）

> 仅保存在本机独立隔离目录，不与主 Bot 或其他 Bot 共享记忆。

## 私密备忘
- （在这里记录财务、健康或私人想法）
''';

/// Animated character shapes adapted from DS-Bot (Apache-2.0).
const kCareAvatarShapes = <String>[
  'acorn',
  'star',
  'moon',
  'wave',
  'kitty',
  'bunny',
  'gumdrop',
  'blossom',
];

const kCareAvatarColors = <String>[
  'sky',
  'blue',
  'mint',
  'violet',
  'coral',
  'amber',
];

class CareBotProfile {
  const CareBotProfile({
    required this.id,
    required this.name,
    required this.roleTitle,
    required this.systemPrompt,
    this.preferredModel = kCareDefaultModel,
    this.preferredEffort = kCareDefaultEffort,
    this.isChief = false,
    this.isPrivate = false,
    this.iconKey = 'acorn',
    this.avatarShape = 'star',
    this.avatarColor = 'sky',
  });

  final String id;
  final String name;
  final String roleTitle;
  final String systemPrompt;
  final String preferredModel;
  final String preferredEffort;
  final bool isChief;
  final bool isPrivate;
  final String iconKey;
  final String avatarShape;
  final String avatarColor;

  CareBotProfile copyWith({
    String? name,
    String? roleTitle,
    String? systemPrompt,
    String? preferredModel,
    String? preferredEffort,
    String? iconKey,
    String? avatarShape,
    String? avatarColor,
  }) =>
      CareBotProfile(
        id: id,
        name: name ?? this.name,
        roleTitle: roleTitle ?? this.roleTitle,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        preferredModel: preferredModel ?? this.preferredModel,
        preferredEffort: preferredEffort ?? this.preferredEffort,
        isChief: isChief,
        isPrivate: isPrivate,
        iconKey: iconKey ?? this.iconKey,
        avatarShape: avatarShape ?? this.avatarShape,
        avatarColor: avatarColor ?? this.avatarColor,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'roleTitle': roleTitle,
        'systemPrompt': systemPrompt,
        'preferredModel': preferredModel,
        'preferredEffort': preferredEffort,
        'isChief': isChief,
        'isPrivate': isPrivate,
        'iconKey': iconKey,
        'avatarShape': avatarShape,
        'avatarColor': avatarColor,
      };

  factory CareBotProfile.fromJson(Map<String, Object?> json) {
    final rawShape = json['avatarShape']?.toString() ?? 'star';
    final rawRole = json['roleTitle']?.toString() ?? '';
    return CareBotProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      roleTitle: rawRole == '专职助手' ? '专职 Bot' : rawRole,
      systemPrompt: json['systemPrompt']?.toString() ?? '',
      preferredModel: _sanitizeModel(json['preferredModel']?.toString()),
      preferredEffort: kCareReasoningEfforts
              .contains(json['preferredEffort']?.toString() ?? '')
          ? json['preferredEffort']!.toString()
          : kCareDefaultEffort,
      isChief: json['isChief'] == true,
      isPrivate: json['isPrivate'] == true,
      iconKey: json['iconKey']?.toString() ?? 'star',
      avatarShape: rawShape == 'care' ? 'acorn' : rawShape,
      avatarColor: json['avatarColor']?.toString() ?? 'sky',
    );
  }

  static String _sanitizeModel(String? raw) {
    final m = raw?.trim() ?? '';
    if (m.isEmpty || kCareLegacyModels.contains(m)) return kCareDefaultModel;
    return m;
  }
}

class CareBotTemplate {
  const CareBotTemplate({
    required this.id,
    required this.name,
    required this.roleTitle,
    required this.systemPrompt,
    required this.preferredModel,
    required this.preferredEffort,
    required this.avatarShape,
    required this.avatarColor,
  });

  final String id;
  final String name;
  final String roleTitle;
  final String systemPrompt;
  final String preferredModel;
  final String preferredEffort;
  final String avatarShape;
  final String avatarColor;
}

const kCareSpecialistTemplates = <CareBotTemplate>[
  CareBotTemplate(
    id: 'travel-planner',
    name: '行程规划 Bot',
    roleTitle: '旅行路线与行前清单',
    systemPrompt: '你是 Care 团队中的行程规划 Bot。用清晰时间线、交通建议和预算清单回答出行问题，简洁务实。',
    preferredModel: 'deepseek-flash',
    preferredEffort: 'low',
    avatarShape: 'wave',
    avatarColor: 'sky',
  ),
  CareBotTemplate(
    id: 'reading-researcher',
    name: '阅读研究 Bot',
    roleTitle: '长文拆解与资料研读',
    systemPrompt: '你是 Care 团队中的阅读研究 Bot。擅长结构化拆解长文、论文与资料库内容，先给核心结论再展开要点。',
    preferredModel: 'deepseek-v4-pro',
    preferredEffort: 'high',
    avatarShape: 'star',
    avatarColor: 'violet',
  ),
  CareBotTemplate(
    id: 'health-coach',
    name: '健康教练 Bot',
    roleTitle: '作息、运动与饮食习惯',
    systemPrompt: '你是 Care 团队中的健康教练 Bot。提供温和、可落地的作息与运动建议，涉及医疗诊断提醒咨询医生。',
    preferredModel: 'deepseek-flash',
    preferredEffort: 'low',
    avatarShape: 'bunny',
    avatarColor: 'mint',
  ),
];

const kChiefBotProfile = CareBotProfile(
  id: kCareChiefBotId,
  name: 'Care Bot',
  roleTitle: '主 Bot · 对话、资料与团队协作',
  systemPrompt: '',
  preferredModel: kCareDefaultModel,
  preferredEffort: kCareDefaultEffort,
  isChief: true,
  isPrivate: false,
  iconKey: 'acorn',
  avatarShape: 'acorn',
  avatarColor: 'blue',
);

const kPrivacyBotProfile = CareBotProfile(
  id: kCarePrivacyBotId,
  name: 'Privacy Bot',
  roleTitle: '独立隔离 · 私密记录与对话',
  systemPrompt:
      '你是 Care 的独立 Privacy Bot。你运行在物理隔离上下文中，绝不引用其他 Bot 或公共记忆，回答克制、保密且尊重边界。',
  preferredModel: kCareDefaultModel,
  preferredEffort: kCareDefaultEffort,
  isChief: false,
  isPrivate: true,
  iconKey: 'lock',
  avatarShape: 'moon',
  avatarColor: 'violet',
);

class CareBiometricStatus {
  const CareBiometricStatus({
    this.biometricReady = false,
    this.deviceSecure = false,
    this.available = false,
  });

  final bool biometricReady;
  final bool deviceSecure;
  final bool available;

  factory CareBiometricStatus.fromMap(Map<String, Object?> map) =>
      CareBiometricStatus(
        biometricReady: map['biometricReady'] == true,
        deviceSecure: map['deviceSecure'] == true,
        available: map['available'] == true,
      );
}

class CareBotsState {
  const CareBotsState({
    this.bots = const [kChiefBotProfile, kPrivacyBotProfile],
    this.activeBotId = kCareChiefBotId,
    this.privacyUnlocked = false,
    this.privacyMemoryMarkdown = '',
    this.biometricStatus = const CareBiometricStatus(),
    this.lastError,
  });

  final List<CareBotProfile> bots;
  final String activeBotId;
  final bool privacyUnlocked;

  /// Loaded ONLY after native biometric/device-credential unlock; cleared on lock!
  final String privacyMemoryMarkdown;
  final CareBiometricStatus biometricStatus;
  final String? lastError;

  CareBotProfile get activeBot => bots.firstWhere(
        (b) => b.id == activeBotId,
        orElse: () => chiefBot,
      );

  CareBotProfile get chiefBot => bots.firstWhere(
        (b) => b.isChief,
        orElse: () => kChiefBotProfile,
      );

  List<CareBotProfile> get specialists =>
      bots.where((b) => !b.isChief && !b.isPrivate).toList();

  CareBotProfile get privacyBot => bots.firstWhere(
        (b) => b.isPrivate,
        orElse: () => kPrivacyBotProfile,
      );

  CareBotProfile? byId(String id) =>
      bots.where((b) => b.id == id).firstOrNull;

  CareBotProfile? findByNameOrId(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final b in bots) {
      if (b.id.toLowerCase() == q || b.name.toLowerCase() == q) return b;
    }
    for (final b in bots) {
      if (b.name.toLowerCase().contains(q)) return b;
    }
    return null;
  }

  CareBotsState copyWith({
    List<CareBotProfile>? bots,
    String? activeBotId,
    bool? privacyUnlocked,
    String? privacyMemoryMarkdown,
    CareBiometricStatus? biometricStatus,
    String? lastError,
    bool clearError = false,
  }) =>
      CareBotsState(
        bots: bots ?? this.bots,
        activeBotId: activeBotId ?? this.activeBotId,
        privacyUnlocked: privacyUnlocked ?? this.privacyUnlocked,
        privacyMemoryMarkdown:
            privacyMemoryMarkdown ?? this.privacyMemoryMarkdown,
        biometricStatus: biometricStatus ?? this.biometricStatus,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

final careVaultPlatformProvider = Provider<CareVaultPlatform>(
  (ref) => MethodChannelCareVaultPlatform(),
);

/// Single owner of Care's Multi-Bot Team & physically-isolated Privacy Bot Vault (M4).
final careBotsProvider =
    AsyncNotifierProvider<CareBotsController, CareBotsState>(
  CareBotsController.new,
);

class CareBotsController extends AsyncNotifier<CareBotsState> {
  int _seq = 0;

  @override
  Future<CareBotsState> build() async {
    final prefs = ref.read(carePrefsStoreProvider);
    final specialists = <CareBotProfile>[];
    final raw = await prefs.getString(kCareBotsPrefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded.whereType<Map>()) {
            final profile = CareBotProfile.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
            );
            if (profile.id.isNotEmpty &&
                !profile.isChief &&
                !profile.isPrivate) {
              specialists.add(profile);
            }
          }
        }
      } catch (_) {}
    }

    var chief = kChiefBotProfile;
    var privacy = kPrivacyBotProfile;
    final coreRaw = await prefs.getString(kCareCoreBotOverridesPrefsKey);
    if (coreRaw != null && coreRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(coreRaw);
        if (decoded is Map) {
          final chiefMap = decoded[kCareChiefBotId];
          if (chiefMap is Map) {
            final rawShape = chiefMap['avatarShape']?.toString();
            final rawModel = chiefMap['preferredModel']?.toString();
            chief = chief.copyWith(
              preferredModel: (rawModel != null && !kCareLegacyModels.contains(rawModel))
                  ? rawModel
                  : null,
              preferredEffort: chiefMap['preferredEffort']?.toString(),
              // Upgrade legacy static app-icon chief avatar to animated DS-Bot mascot
              avatarShape: (rawShape == null || rawShape == 'care')
                  ? 'acorn'
                  : rawShape,
              avatarColor: chiefMap['avatarColor']?.toString(),
            );
          }
          final privMap = decoded[kCarePrivacyBotId];
          if (privMap is Map) {
            final rawModel = privMap['preferredModel']?.toString();
            privacy = privacy.copyWith(
              preferredModel: (rawModel != null && !kCareLegacyModels.contains(rawModel))
                  ? rawModel
                  : null,
              preferredEffort: privMap['preferredEffort']?.toString(),
              avatarShape: privMap['avatarShape']?.toString(),
              avatarColor: privMap['avatarColor']?.toString(),
            );
          }
        }
      } catch (_) {}
    } else {
      final savedSettings = ref.read(careSettingsProvider).value;
      if (savedSettings != null) {
        chief = chief.copyWith(
          preferredModel: savedSettings.activeModel,
          preferredEffort: savedSettings.activeEffort,
        );
      }
    }

    CareBiometricStatus bio = const CareBiometricStatus();
    try {
      final rawBio =
          await ref.read(careVaultPlatformProvider).biometricStatus();
      bio = CareBiometricStatus.fromMap(rawBio);
    } catch (_) {}

    return CareBotsState(
      bots: [chief, ...specialists, privacy],
      activeBotId: kCareChiefBotId,
      privacyUnlocked: false,
      privacyMemoryMarkdown: '',
      biometricStatus: bio,
    );
  }

  Future<void> _persistSpecialists(List<CareBotProfile> allBots) {
    final specialists = allBots
        .where((b) => !b.isChief && !b.isPrivate)
        .map((b) => b.toJson())
        .toList();
    return ref
        .read(carePrefsStoreProvider)
        .setString(kCareBotsPrefsKey, jsonEncode(specialists));
  }

  Future<void> _persistCoreOverrides(List<CareBotProfile> allBots) {
    final chief = allBots.firstWhere(
      (b) => b.isChief,
      orElse: () => kChiefBotProfile,
    );
    final privacy = allBots.firstWhere(
      (b) => b.isPrivate,
      orElse: () => kPrivacyBotProfile,
    );
    return ref.read(carePrefsStoreProvider).setString(
          kCareCoreBotOverridesPrefsKey,
          jsonEncode({
            kCareChiefBotId: {
              'preferredModel': chief.preferredModel,
              'preferredEffort': chief.preferredEffort,
              'avatarShape': chief.avatarShape,
              'avatarColor': chief.avatarColor,
            },
            kCarePrivacyBotId: {
              'preferredModel': privacy.preferredModel,
              'preferredEffort': privacy.preferredEffort,
              'avatarShape': privacy.avatarShape,
              'avatarColor': privacy.avatarColor,
            },
          }),
        );
  }

  Future<CareBotProfile> spawnSpecialist({
    required String name,
    required String roleTitle,
    required String systemPrompt,
    String preferredModel = kCareDefaultModel,
    String preferredEffort = kCareDefaultEffort,
    String avatarShape = 'star',
    String avatarColor = 'sky',
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const FormatException('Bot name is required.');
    }
    final current = state.value ?? await future;
    final safeShape = kCareAvatarShapes.contains(avatarShape) ? avatarShape : 'star';
    final safeColor = kCareAvatarColors.contains(avatarColor) ? avatarColor : 'sky';
    final safeModel = preferredModel.trim().isEmpty ||
            kCareLegacyModels.contains(preferredModel.trim())
        ? kCareDefaultModel
        : preferredModel.trim();

    final bot = CareBotProfile(
      id: 'bot-${DateTime.now().microsecondsSinceEpoch}-${++_seq}',
      name: cleanName,
      roleTitle: roleTitle.trim().isEmpty ? '专职 Bot' : roleTitle.trim(),
      systemPrompt: systemPrompt.trim().isEmpty
          ? '你是 Care 团队中的专职 Bot「$cleanName」，请围绕你的专长简洁高效地帮助用户。'
          : systemPrompt.trim(),
      preferredModel: safeModel,
      preferredEffort: kCareReasoningEfforts.contains(preferredEffort)
          ? preferredEffort
          : kCareDefaultEffort,
      isChief: false,
      isPrivate: false,
      iconKey: safeShape,
      avatarShape: safeShape,
      avatarColor: safeColor,
    );
    final nextBots = [
      current.chiefBot,
      ...current.specialists,
      bot,
      current.privacyBot,
    ];
    await _persistSpecialists(nextBots);
    state = AsyncData(current.copyWith(bots: nextBots, clearError: true));
    return bot;
  }

  Future<CareBotProfile> spawnFromTemplate(String templateId) async {
    final tpl = kCareSpecialistTemplates.firstWhere(
      (t) => t.id == templateId,
      orElse: () => throw StateError('Unknown template: $templateId'),
    );
    final current = state.value ?? await future;
    final existing = current.specialists.where((b) => b.name == tpl.name);
    if (existing.isNotEmpty) return existing.first;
    return spawnSpecialist(
      name: tpl.name,
      roleTitle: tpl.roleTitle,
      systemPrompt: tpl.systemPrompt,
      preferredModel: tpl.preferredModel,
      preferredEffort: tpl.preferredEffort,
      avatarShape: tpl.avatarShape,
      avatarColor: tpl.avatarColor,
    );
  }

  /// Updates model, thinking effort, or animated avatar for ANY bot.
  Future<void> updateBotConfig(
    String botId, {
    String? preferredModel,
    String? preferredEffort,
    String? avatarShape,
    String? avatarColor,
    String? name,
    String? roleTitle,
    String? systemPrompt,
  }) async {
    final current = state.value ?? await future;
    final nextBots = current.bots.map((b) {
      if (b.id != botId) return b;
      return b.copyWith(
        preferredModel: preferredModel?.trim().isNotEmpty == true &&
                !kCareLegacyModels.contains(preferredModel!.trim())
            ? preferredModel.trim()
            : null,
        preferredEffort: preferredEffort != null &&
                kCareReasoningEfforts.contains(preferredEffort)
            ? preferredEffort
            : null,
        avatarShape: avatarShape,
        avatarColor: avatarColor,
        name: (!b.isChief && !b.isPrivate && name?.trim().isNotEmpty == true)
            ? name!.trim()
            : null,
        roleTitle: (!b.isChief && !b.isPrivate) ? roleTitle?.trim() : null,
        systemPrompt: (!b.isChief && !b.isPrivate) ? systemPrompt?.trim() : null,
      );
    }).toList();

    await _persistSpecialists(nextBots);
    await _persistCoreOverrides(nextBots);
    if (botId == kCareChiefBotId) {
      if (preferredModel != null &&
          preferredModel.trim().isNotEmpty &&
          !kCareLegacyModels.contains(preferredModel.trim())) {
        await ref
            .read(careSettingsProvider.notifier)
            .setActiveModel(preferredModel);
      }
      if (preferredEffort != null &&
          kCareReasoningEfforts.contains(preferredEffort)) {
        await ref
            .read(careSettingsProvider.notifier)
            .setActiveEffort(preferredEffort);
      }
    }
    state = AsyncData(current.copyWith(bots: nextBots, clearError: true));
  }

  Future<void> deleteSpecialist(String botId) async {
    final current = state.value ?? await future;
    final target = current.bots.where((b) => b.id == botId).firstOrNull;
    if (target == null || target.isChief || target.isPrivate) return;
    final nextBots = current.bots.where((b) => b.id != botId).toList();
    await _persistSpecialists(nextBots);
    final nextActive =
        current.activeBotId == botId ? kCareChiefBotId : current.activeBotId;
    state = AsyncData(
      current.copyWith(
        bots: nextBots,
        activeBotId: nextActive,
        clearError: true,
      ),
    );
  }

  Future<void> replaceSpecialistsFromBackup(
    List<CareBotProfile> restored,
  ) async {
    final current = state.value ?? await future;
    final clean = restored
        .where((b) => b.id.isNotEmpty && !b.isChief && !b.isPrivate)
        .toList();
    final nextBots = [current.chiefBot, ...clean, current.privacyBot];
    await _persistSpecialists(nextBots);
    state = AsyncData(current.copyWith(bots: nextBots, clearError: true));
  }

  /// Selects an active conversation persona.
  /// Switching to the Privacy Bot is refused while locked (AGENTS.md §1.4).
  Future<bool> selectActiveBot(String botId) async {
    final current = state.value ?? await future;
    final target = current.bots.where((b) => b.id == botId).firstOrNull;
    if (target == null) return false;
    if (target.isPrivate && !current.privacyUnlocked) {
      state = AsyncData(
        current.copyWith(lastError: 'Privacy Bot 尚未解锁，请先验证身份。'),
      );
      return false;
    }
    state = AsyncData(
      current.copyWith(activeBotId: target.id, clearError: true),
    );
    return true;
  }

  /// Unlocks the physically isolated Privacy Bot Vault via native biometric/lock screen.
  Future<bool> unlockPrivacyVault() async {
    final current = state.value ?? await future;
    final vault = ref.read(careVaultPlatformProvider);
    final res = await vault.authenticate(
      title: '解锁 Privacy Bot',
      subtitle: '验证身份后可访问独立隔离的私密对话与笔记',
    );
    if (res['authenticated'] != true) {
      final unsecured = res['deviceUnsecured'] == true;
      state = AsyncData(
        current.copyWith(
          privacyUnlocked: false,
          lastError: unsecured
              ? '请先在系统设置中开启锁屏密码或指纹/面容。'
              : (res['reason']?.toString().isNotEmpty == true
                  ? res['reason'].toString()
                  : '未通过身份验证'),
        ),
      );
      return false;
    }

    var doc = await vault.readPrivacyDoc(
      botId: kCarePrivacyBotId,
      filename: kCarePrivacyMemoryFile,
    );
    if (doc == null || doc.trim().isEmpty) {
      doc = kDefaultPrivacyMemoryMarkdown;
      await vault.writePrivacyDoc(
        botId: kCarePrivacyBotId,
        filename: kCarePrivacyMemoryFile,
        content: doc,
      );
    }

    state = AsyncData(
      current.copyWith(
        privacyUnlocked: true,
        privacyMemoryMarkdown: doc,
        clearError: true,
      ),
    );
    return true;
  }

  /// Immediately locks Privacy Vault, clears private text from memory, and returns to Chief if needed.
  void lockPrivacyVault() {
    final current = state.value;
    if (current == null) return;
    final nextActive =
        current.activeBot.isPrivate ? kCareChiefBotId : current.activeBotId;
    state = AsyncData(
      current.copyWith(
        privacyUnlocked: false,
        privacyMemoryMarkdown: '',
        activeBotId: nextActive,
        clearError: true,
      ),
    );
  }

  /// Writes exclusively to the physical Privacy Vault directory (never shared MEMORY.md).
  Future<void> savePrivacyMemory(String markdown) async {
    final current = state.value ?? await future;
    if (!current.privacyUnlocked) {
      throw StateError('Privacy Vault is locked.');
    }
    await ref.read(careVaultPlatformProvider).writePrivacyDoc(
          botId: kCarePrivacyBotId,
          filename: kCarePrivacyMemoryFile,
          content: markdown,
        );
    state = AsyncData(
      current.copyWith(privacyMemoryMarkdown: markdown, clearError: true),
    );
  }

  /// Enforces AGENTS.md §1.4 & §1.3: any export out of Privacy Bot MUST go through
  /// native Kotlin SafetyGate approval (`privacy_cross_bot_export`).
  Future<bool> requestPrivacyExport({
    required String summary,
    String target = 'chief',
  }) async {
    final current = state.value ?? await future;
    if (!current.privacyUnlocked) return false;
    final gate = await ref.read(careSafetyPlatformProvider).evaluateAction(
          action: 'privacy_cross_bot_export',
          summary: summary,
          target: target,
        );
    await ref.read(careSafetyProvider.notifier).refresh();
    return gate['allowed'] == true && gate['requiresApproval'] != true;
  }

  Future<void> wipePrivacyVault() async {
    final current = state.value ?? await future;
    await ref.read(careVaultPlatformProvider).wipePrivacyVault(kCarePrivacyBotId);
    final nextActive =
        current.activeBot.isPrivate ? kCareChiefBotId : current.activeBotId;
    state = AsyncData(
      current.copyWith(
        privacyUnlocked: false,
        privacyMemoryMarkdown: '',
        activeBotId: nextActive,
        clearError: true,
      ),
    );
  }
}
