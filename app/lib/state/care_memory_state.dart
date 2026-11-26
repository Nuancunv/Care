import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/care_storage.dart';

const kSoulFilename = 'SOUL.md';
const kMemoryFilename = 'MEMORY.md';

const kDefaultSoulMarkdown = '''# SOUL.md — Care 个人助手人格与边界

## 身份定位
- 名称：Care（首席个人管家）
- 角色：常驻于用户 Android 手机本机的私密个人 AI 助手，擅长日程协同、生活提醒与信息整理。

## 沟通风格
- 简洁自然、主动给出结论与下一步建议，不堆砌冗长模板。

## 安全红线（不可覆盖）
- 任何高风险操作（外发消息/邮件、删除文件、支付、无障碍写入）必须经由原生 SafetyGate 审批通过。
''';

const kDefaultMemoryMarkdown = '''# MEMORY.md — 用户透明长期记忆

> 本文件仅存储于手机本机私有目录，随时可查看、编辑或删除。

## 1. 基础画像与偏好
- 称呼：
- 时区：Asia/Shanghai
- 免打扰时段：23:00 - 07:30

## 2. 长期目标与进行中事项
- （随对话与手动编辑持续沉淀）
''';

class CareMemoryState {
  const CareMemoryState({
    required this.soulMarkdown,
    required this.memoryMarkdown,
    this.lastSavedAt,
    this.isSaving = false,
  });

  final String soulMarkdown;
  final String memoryMarkdown;
  final DateTime? lastSavedAt;
  final bool isSaving;

  CareMemoryState copyWith({
    String? soulMarkdown,
    String? memoryMarkdown,
    DateTime? lastSavedAt,
    bool? isSaving,
  }) {
    return CareMemoryState(
      soulMarkdown: soulMarkdown ?? this.soulMarkdown,
      memoryMarkdown: memoryMarkdown ?? this.memoryMarkdown,
      lastSavedAt: lastSavedAt ?? this.lastSavedAt,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

final careDocumentStoreProvider = Provider<CareDocumentStore>(
  (ref) => LocalCareDocumentStore(),
);

/// Single owner of transparent plain-Markdown `SOUL.md` & `MEMORY.md` (AGENTS.md §3.3).
final careMemoryProvider =
    AsyncNotifierProvider<CareMemoryController, CareMemoryState>(
  CareMemoryController.new,
);

class CareMemoryController extends AsyncNotifier<CareMemoryState> {
  @override
  Future<CareMemoryState> build() async {
    final store = ref.read(careDocumentStoreProvider);
    var soul = await store.readDocument(kSoulFilename);
    var memory = await store.readDocument(kMemoryFilename);

    if (soul == null) {
      soul = kDefaultSoulMarkdown;
      await store.writeDocument(kSoulFilename, soul);
    }
    if (memory == null) {
      memory = kDefaultMemoryMarkdown;
      await store.writeDocument(kMemoryFilename, memory);
    }

    return CareMemoryState(soulMarkdown: soul, memoryMarkdown: memory);
  }

  Future<void> saveSoul(String markdown) async {
    final current = state.value ?? await future;
    state = AsyncData(current.copyWith(isSaving: true));
    await ref.read(careDocumentStoreProvider).writeDocument(kSoulFilename, markdown);
    state = AsyncData(
      current.copyWith(
        soulMarkdown: markdown,
        lastSavedAt: DateTime.now(),
        isSaving: false,
      ),
    );
  }

  Future<void> saveMemory(String markdown) async {
    final current = state.value ?? await future;
    state = AsyncData(current.copyWith(isSaving: true));
    await ref
        .read(careDocumentStoreProvider)
        .writeDocument(kMemoryFilename, markdown);
    state = AsyncData(
      current.copyWith(
        memoryMarkdown: markdown,
        lastSavedAt: DateTime.now(),
        isSaving: false,
      ),
    );
  }

  Future<void> resetDefaults() async {
    final store = ref.read(careDocumentStoreProvider);
    await store.writeDocument(kSoulFilename, kDefaultSoulMarkdown);
    await store.writeDocument(kMemoryFilename, kDefaultMemoryMarkdown);
    state = AsyncData(
      CareMemoryState(
        soulMarkdown: kDefaultSoulMarkdown,
        memoryMarkdown: kDefaultMemoryMarkdown,
        lastSavedAt: DateTime.now(),
      ),
    );
  }
}
