import 'package:care_app/services/care_deepseek_direct.dart';
import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../care_theme.dart';
import '../chat/care_chat_page.dart';
import '../chat/care_model_sheet.dart';
import '../common/care_bot_avatar.dart';
import '../common/care_copy.dart';
import '../common/care_markdown_view.dart';
import '../common/care_widgets.dart';

/// Keyboard-safe full-height bottom sheet for creating a new Bot.
/// Includes one-tap preset templates and inline ChoiceChips for Model & Thinking
/// Effort (NO floating dropdowns), eliminating keyboard-resize misalignment.
Future<CareBotProfile?> showCareCreateBotSheet(BuildContext context) {
  return showModalBottomSheet<CareBotProfile>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _CreateBotSheet(),
  );
}

/// Modal sheet for viewing/editing Privacy Bot's physically isolated notes
/// directly from Privacy Bot's chat AppBar (zero intermediate page needed).
Future<void> showCarePrivacyNotesSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _PrivacyNotesSheet(),
  );
}

/// 「Bot 团队与隐私 Bot」管理页.
class CareBotsPage extends ConsumerStatefulWidget {
  const CareBotsPage({super.key});

  @override
  ConsumerState<CareBotsPage> createState() => _CareBotsPageState();
}

class _CareBotsPageState extends ConsumerState<CareBotsPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      final bots = ref.read(careBotsProvider).value;
      if (bots?.privacyUnlocked == true) {
        ref.read(careBotsProvider.notifier).lockPrivacyVault();
        ref.read(careChatProvider.notifier).purgeBotThread(kCarePrivacyBotId);
      }
    }
  }

  Future<void> _openBotChat(
    String botId, {
    CareBotProfile? profile,
  }) async {
    final ok = await ref.read(careBotsProvider.notifier).selectActiveBot(botId);
    if (!mounted) return;
    if (!ok) {
      final err = ref.read(careBotsProvider).value?.lastError;
      showCareSnack(context, err ?? '暂时无法切换 Bot。');
      return;
    }
    final resolved = profile ?? ref.read(careBotsProvider).value?.activeBot;
    ref.read(careChatProvider.notifier).syncActiveBot(botId, profile: resolved);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CareChatPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final botsAsync = ref.watch(careBotsProvider);
    final settings = ref.watch(careSettingsProvider).value;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return CareAtmosphereBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Bot 团队与隐私空间')),
        body: botsAsync.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: FilledButton(
              onPressed: () => ref.invalidate(careBotsProvider),
              child: const Text('重试'),
            ),
          ),
          data: (s) {
            final chief = s.chiefBot;
            final chiefModel = settings?.activeModel ?? chief.preferredModel;
            final chiefEffort = settings?.activeEffort ?? chief.preferredEffort;
            return CareContentWidth(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  // ── Chief Bot Card ──
                  Card(
                    color: s.activeBotId == kCareChiefBotId
                        ? scheme.primaryContainer.withValues(alpha: 0.55)
                        : null,
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                      leading: CareBotAvatar.forBot(chief, size: 42),
                      title: Row(
                        children: [
                          Text(
                            '${chief.name} · 主 Bot',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (s.activeBotId == kCareChiefBotId) ...[
                            const SizedBox(width: 8),
                            _ActiveBadge(color: scheme.primary),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        '${careModelShortLabel(chiefModel)} · ${careEffortShortLabel(chiefEffort)}',
                      ),
                      trailing: IconButton(
                        tooltip: '模型与思考',
                        icon: const Icon(Icons.tune_rounded, size: 20),
                        onPressed: () =>
                            showCareModelEffortSheet(context, bot: chief),
                      ),
                      onTap: () => _openBotChat(kCareChiefBotId, profile: chief),
                    ),
                  ),

                  // ── Specialist Bots Section ──
                  Padding(
                    padding: const EdgeInsets.only(top: 22, bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '专职 Bot',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final created = await showCareCreateBotSheet(context);
                            if (created != null && context.mounted) {
                              ref
                                  .read(careChatProvider.notifier)
                                  .seedSpecialistGreetingIfEmpty(created);
                              await _openBotChat(created.id, profile: created);
                            }
                          },
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('新建 Bot'),
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tpl in kCareSpecialistTemplates)
                        ActionChip(
                          avatar: CareBotAvatar(
                            shape: tpl.avatarShape,
                            colorKey: tpl.avatarColor,
                            size: 22,
                            interactive: false,
                          ),
                          label: Text('+ ${tpl.name}'),
                          shape: const StadiumBorder(),
                          side: BorderSide(color: scheme.outlineVariant),
                          backgroundColor: scheme.surfaceContainerLow,
                          onPressed: () async {
                            try {
                              final bot = await ref
                                  .read(careBotsProvider.notifier)
                                  .spawnFromTemplate(tpl.id);
                              ref
                                  .read(careChatProvider.notifier)
                                  .seedSpecialistGreetingIfEmpty(bot);
                              if (context.mounted) {
                                showCareSnack(context, '已添加「${bot.name}」，点击即可对话');
                              }
                            } catch (_) {
                              if (context.mounted) {
                                showCareSnack(context, '创建失败，请稍后再试。');
                              }
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (s.specialists.isEmpty)
                    const CareHintCard(
                      icon: Icons.groups_outlined,
                      title: '暂无专职 Bot',
                      body: '点上方模板或「新建 Bot」添加，也可直接让主 Bot 帮你创建。',
                    )
                  else
                    Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < s.specialists.length; i++) ...[
                            if (i > 0) const Divider(indent: 18, endIndent: 18),
                            _SpecialistTile(
                              bot: s.specialists[i],
                              active: s.activeBotId == s.specialists[i].id,
                              onSelect: () => _openBotChat(
                                s.specialists[i].id,
                                profile: s.specialists[i],
                              ),
                              onConfigure: () => showCareModelEffortSheet(
                                context,
                                bot: s.specialists[i],
                              ),
                              onDelete: () async {
                                final bot = s.specialists[i];
                                final ok = await showCareConfirmDialog(
                                  context,
                                  title: '移除「${bot.name}」？',
                                  message: '公共记忆不受影响。',
                                  confirmLabel: '移除',
                                  destructive: true,
                                );
                                if (ok) {
                                  ref
                                      .read(careChatProvider.notifier)
                                      .purgeBotThread(bot.id);
                                  await ref
                                      .read(careBotsProvider.notifier)
                                      .deleteSpecialist(bot.id);
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    ),

                  // ── Privacy Bot Section ──
                  Padding(
                    padding: const EdgeInsets.only(top: 24, bottom: 8),
                    child: Text(
                      'Privacy Bot',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  _PrivacyVaultCard(
                    state: s,
                    onEnterPrivateChat: () => _openBotChat(
                      kCarePrivacyBotId,
                      profile: s.privacyBot,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        '当前',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _SpecialistTile extends StatelessWidget {
  const _SpecialistTile({
    required this.bot,
    required this.active,
    required this.onSelect,
    required this.onConfigure,
    required this.onDelete,
  });

  final CareBotProfile bot;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onConfigure;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      leading: CareBotAvatar.forBot(bot, size: 42),
      title: Row(
        children: [
          Flexible(
            child: Text(
              bot.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (active) ...[
            const SizedBox(width: 8),
            _ActiveBadge(color: scheme.primary),
          ],
        ],
      ),
      subtitle: Text(
        '${careModelShortLabel(bot.preferredModel)} · ${careEffortShortLabel(bot.preferredEffort)} · ${bot.roleTitle}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '模型与思考',
            icon: Icon(Icons.tune_rounded,
                size: 19, color: scheme.onSurfaceVariant),
            onPressed: onConfigure,
          ),
          IconButton(
            tooltip: '移除 ${bot.name}',
            icon: Icon(Icons.delete_outline_rounded,
                size: 19, color: scheme.onSurfaceVariant),
            onPressed: onDelete,
          ),
        ],
      ),
      onTap: onSelect,
    );
  }
}

class _PrivacyVaultCard extends ConsumerStatefulWidget {
  const _PrivacyVaultCard({
    required this.state,
    required this.onEnterPrivateChat,
  });

  final CareBotsState state;
  final VoidCallback onEnterPrivateChat;

  @override
  ConsumerState<_PrivacyVaultCard> createState() => _PrivacyVaultCardState();
}

class _PrivacyVaultCardState extends ConsumerState<_PrivacyVaultCard> {
  final _noteCtrl = TextEditingController();
  bool _editing = false;
  bool _busy = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() => _busy = true);
    try {
      final ok = await ref.read(careBotsProvider.notifier).unlockPrivacyVault();
      if (!mounted) return;
      if (!ok) {
        final err = ref.read(careBotsProvider).value?.lastError;
        showCareSnack(context, err ?? '未通过身份验证');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _lock() {
    setState(() => _editing = false);
    ref.read(careBotsProvider.notifier).lockPrivacyVault();
    ref.read(careChatProvider.notifier).purgeBotThread(kCarePrivacyBotId);
    showCareSnack(context, '隐私 Bot 已上锁');
  }

  Future<void> _saveNotes() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(careBotsProvider.notifier)
          .savePrivacyMemory(_noteCtrl.text);
      if (mounted) {
        setState(() => _editing = false);
        showCareSnack(context, '已保存至隔离目录');
      }
    } catch (_) {
      if (mounted) showCareSnack(context, '保存失败，请稍后再试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportWithGate() async {
    try {
      await ref.read(careBotsProvider.notifier).requestPrivacyExport(
            summary: '将隐私 Bot 中的笔记摘要分享到主 Bot 对话中',
            target: 'chief',
          );
      if (mounted) showCareSnack(context, '已提交安全门审批');
    } catch (_) {
      if (mounted) showCareSnack(context, '发起审批失败，请稍后再试。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!s.privacyUnlocked) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CareBotAvatar.forBot(s.privacyBot, size: 46),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Privacy Bot（已锁定）',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '独立隔离 · 切后台自动上锁',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                  ),
                  onPressed: _busy ? null : _unlock,
                  icon: const Icon(Icons.fingerprint_rounded, size: 18),
                  label: Text(_busy ? '验证中…' : '解锁隐私空间'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CareBotAvatar.forBot(s.privacyBot, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Privacy Bot · 已解锁',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: '模型与思考',
                  icon: const Icon(Icons.tune_rounded, size: 19),
                  onPressed: () =>
                      showCareModelEffortSheet(context, bot: s.privacyBot),
                ),
                TextButton.icon(
                  onPressed: _lock,
                  icon: const Icon(Icons.lock_outline_rounded, size: 17),
                  label: const Text('上锁'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_editing) ...[
              TextField(
                controller: _noteCtrl,
                minLines: 4,
                maxLines: 8,
                enabled: !_busy,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontFamily: 'monospace', height: 1.5),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _busy ? null : () => setState(() => _editing = false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style:
                        FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                    onPressed: _busy ? null : _saveNotes,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: CareMarkdownView(
                  markdown: s.privacyMemoryMarkdown,
                  baseStyle: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    style:
                        FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                    onPressed: widget.onEnterPrivateChat,
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                    label: const Text('进入私密对话'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(64, 40)),
                    onPressed: () {
                      _noteCtrl.text = s.privacyMemoryMarkdown;
                      setState(() => _editing = true);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('编辑笔记'),
                  ),
                  TextButton.icon(
                    onPressed: _exportWithGate,
                    icon: const Icon(Icons.shield_outlined, size: 17),
                    label: const Text('申请导出'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreateBotSheet extends ConsumerStatefulWidget {
  const _CreateBotSheet();

  @override
  ConsumerState<_CreateBotSheet> createState() => _CreateBotSheetState();
}

class _CreateBotSheetState extends ConsumerState<_CreateBotSheet> {
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _prompt = TextEditingController();
  String _model = kCareDefaultModel;
  String _effort = kCareDefaultEffort;
  String _shape = 'star';
  String _color = 'sky';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '请给 Bot 起个名字');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bot = await ref.read(careBotsProvider.notifier).spawnSpecialist(
            name: _name.text,
            roleTitle: _role.text,
            systemPrompt: _prompt.text,
            preferredModel: _model,
            preferredEffort: _effort,
            avatarShape: _shape,
            avatarColor: _color,
          );
      if (mounted) Navigator.of(context).pop(bot);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '创建失败，请稍后再试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final models = <String>{
      ...?ref
          .watch(careSettingsProvider)
          .value
          ?.availableModels
          .where((m) => !kCareLegacyModels.contains(m)),
      ...kCareDefaultModels,
      if (!kCareLegacyModels.contains(_model)) _model,
    }.toList();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '新建 Bot',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final tpl in kCareSpecialistTemplates)
                    ActionChip(
                      avatar: CareBotAvatar(
                        shape: tpl.avatarShape,
                        colorKey: tpl.avatarColor,
                        size: 20,
                        interactive: false,
                      ),
                      label: Text(tpl.name),
                      shape: const StadiumBorder(),
                      onPressed: _busy
                          ? null
                          : () {
                              FocusScope.of(context).unfocus();
                              setState(() {
                                _name.text = tpl.name;
                                _role.text = tpl.roleTitle;
                                _prompt.text = tpl.systemPrompt;
                                _shape = tpl.avatarShape;
                                _color = tpl.avatarColor;
                                _model = tpl.preferredModel;
                                _effort = tpl.preferredEffort;
                                _error = null;
                              });
                            },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: CareBotAvatar(
                  shape: _shape,
                  colorKey: _color,
                  size: 62,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final sh in kCareAvatarShapes)
                    ChoiceChip(
                      showCheckmark: false,
                      padding: const EdgeInsets.all(4),
                      label: CareBotAvatar(
                        shape: sh,
                        colorKey: _color,
                        size: 24,
                        interactive: false,
                      ),
                      selected: _shape == sh,
                      onSelected: _busy
                          ? null
                          : (_) {
                              FocusScope.of(context).unfocus();
                              setState(() => _shape = sh);
                            },
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final c in kCareAvatarColors)
                    ChoiceChip(
                      showCheckmark: false,
                      label: Text(
                        switch (c) {
                          'sky' => '晴蓝',
                          'blue' => '深蓝',
                          'mint' => '薄荷',
                          'violet' => '星紫',
                          'coral' => '珊瑚',
                          _ => '暖橘',
                        },
                        style: TextStyle(
                          fontSize: 12,
                          color: _color == c
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      selected: _color == c,
                      onSelected: _busy
                          ? null
                          : (_) {
                              FocusScope.of(context).unfocus();
                              setState(() => _color = c);
                            },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Bot 名称',
                  hintText: '例如：Study / Finance / 代码 Bot',
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _role,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '职责简介',
                  hintText: '例如：备考复习与资料梳理',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _prompt,
                enabled: !_busy,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '专属指令（可选）',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '模型',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in models)
                    ChoiceChip(
                      label: Text(careModelLabel(m)),
                      selected: _model == m,
                      onSelected: _busy
                          ? null
                          : (_) {
                              FocusScope.of(context).unfocus();
                              setState(() => _model = m);
                            },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '思考强度',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in kCareReasoningEfforts)
                    ChoiceChip(
                      label: Text(careEffortLabel(e)),
                      selected: _effort == e,
                      onSelected: _busy
                          ? null
                          : (_) {
                              FocusScope.of(context).unfocus();
                              setState(() => _effort = e);
                            },
                    ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _create,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Text('创建并开始对话'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyNotesSheet extends ConsumerStatefulWidget {
  const _PrivacyNotesSheet();

  @override
  ConsumerState<_PrivacyNotesSheet> createState() => _PrivacyNotesSheetState();
}

class _PrivacyNotesSheetState extends ConsumerState<_PrivacyNotesSheet> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl.text = ref.read(careBotsProvider).value?.privacyMemoryMarkdown ?? '';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(careBotsProvider.notifier).savePrivacyMemory(_ctrl.text);
      if (mounted) {
        Navigator.of(context).pop();
        showCareSnack(context, '已保存至隔离目录');
      }
    } catch (_) {
      if (mounted) showCareSnack(context, '保存失败，请稍后再试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportWithGate() async {
    try {
      await ref.read(careBotsProvider.notifier).requestPrivacyExport(
            summary: '将 Privacy Bot 中的笔记摘要分享到主 Bot 对话中',
            target: 'chief',
          );
      if (mounted) showCareSnack(context, '已提交安全门审批');
    } catch (_) {
      if (mounted) showCareSnack(context, '发起审批失败，请稍后再试。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Privacy Bot 私密笔记',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: _exportWithGate,
                  icon: const Icon(Icons.shield_outlined, size: 17),
                  label: const Text('申请导出'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ctrl,
              minLines: 6,
              maxLines: 12,
              enabled: !_busy,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontFamily: 'monospace', height: 1.5),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('保存到隔离目录'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
