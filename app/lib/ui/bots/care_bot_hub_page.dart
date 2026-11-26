import 'package:care_app/state/care_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../automation/care_automation_page.dart';
import '../care_theme.dart';
import '../chat/care_chat_page.dart';
import '../chat/care_model_sheet.dart';
import '../common/care_bot_avatar.dart';
import '../common/care_copy.dart';
import '../common/care_widgets.dart';
import '../memory/care_memory_page.dart';
import '../settings/care_settings_page.dart';
import '../today/care_today_page.dart';
import '../workspace/care_workspace_page.dart';
import 'care_bots_page.dart';

/// First-level Bot Hub Home Screen:
/// - Chief Bot (`Care Bot`) fixed ONLY at the top hero (never duplicated in list)
/// - Specialist Bots listed cleanly below with latest preview, timestamp & unread dot
/// - `Privacy Bot` completely hidden by default — revealed via an elastic pull-up
///   over-scroll gesture at the bottom (with haptic detent + smooth transition)
///   or discreetly by typing `privacy` in the search bar.
class CareBotHubPage extends ConsumerStatefulWidget {
  const CareBotHubPage({super.key});

  @override
  ConsumerState<CareBotHubPage> createState() => _CareBotHubPageState();
}

class _CareBotHubPageState extends ConsumerState<CareBotHubPage>
    with WidgetsBindingObserver {
  static const double _kPrivacyTriggerPx = 82.0;

  final _searchCtrl = TextEditingController();
  String _query = '';
  double _pullUpOverscroll = 0.0;
  bool _privacyArmed = false;
  bool _unlockingPrivacy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
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

  Future<void> _enterBot(CareBotProfile bot) async {
    FocusScope.of(context).unfocus();
    if (bot.isPrivate) {
      if (_unlockingPrivacy) return;
      _unlockingPrivacy = true;
      try {
        final unlocked =
            ref.read(careBotsProvider).value?.privacyUnlocked == true;
        if (!unlocked) {
          final ok =
              await ref.read(careBotsProvider.notifier).unlockPrivacyVault();
          if (!mounted) return;
          if (!ok) {
            final err = ref.read(careBotsProvider).value?.lastError;
            showCareSnack(context, err ?? '未通过身份验证');
            return;
          }
        }
      } finally {
        _unlockingPrivacy = false;
      }
    }
    final ok = await ref.read(careBotsProvider.notifier).selectActiveBot(bot.id);
    if (!mounted || !ok) return;
    ref.read(careChatProvider.notifier).syncActiveBot(bot.id, profile: bot);
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: Duration(milliseconds: bot.isPrivate ? 320 : 240),
        pageBuilder: (_, _, _) => const CareChatPage(),
        transitionsBuilder: (_, anim, _, child) {
          if (bot.isPrivate) {
            final curved = CurvedAnimation(
              parent: anim,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.08),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          }
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: child,
          );
        },
      ),
    );
  }

  bool _onScrollNotification(
    ScrollNotification notification,
    CareBotProfile privacyBot,
  ) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final over =
        (notification.metrics.pixels - notification.metrics.maxScrollExtent)
            .clamp(0.0, 150.0);

    if (notification is ScrollUpdateNotification) {
      if (over > 0 || _pullUpOverscroll > 0) {
        final armedNow = over >= _kPrivacyTriggerPx;
        if (armedNow && !_privacyArmed) {
          HapticFeedback.mediumImpact();
        }
        setState(() {
          _pullUpOverscroll = over;
          _privacyArmed = armedNow;
        });
      }
    } else if (notification is OverscrollNotification &&
        notification.overscroll > 0) {
      final next = (_pullUpOverscroll + notification.overscroll).clamp(0.0, 150.0);
      final armedNow = next >= _kPrivacyTriggerPx;
      if (armedNow && !_privacyArmed) {
        HapticFeedback.mediumImpact();
      }
      setState(() {
        _pullUpOverscroll = next;
        _privacyArmed = armedNow;
      });
    } else if (notification is ScrollEndNotification) {
      final shouldTrigger = _privacyArmed;
      if (_pullUpOverscroll > 0 || _privacyArmed) {
        setState(() {
          _pullUpOverscroll = 0.0;
          _privacyArmed = false;
        });
      }
      if (shouldTrigger) {
        _enterBot(privacyBot);
      }
    }
    return false;
  }

  Future<void> _createBot() async {
    FocusScope.of(context).unfocus();
    final created = await showCareCreateBotSheet(context);
    if (created == null || !mounted) return;
    ref.read(careChatProvider.notifier).seedSpecialistGreetingIfEmpty(created);
    await _enterBot(created);
  }

  Future<void> _openBotActions(CareBotProfile bot) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CareBotAvatar.forBot(bot, size: 34, interactive: false),
                title: Text(
                  bot.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${careModelShortLabel(bot.preferredModel)} · ${careEffortShortLabel(bot.preferredEffort)}',
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('模型与思考配置'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showCareModelEffortSheet(context, bot: bot);
                },
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('打开资料库'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final ok = await ref
                      .read(careBotsProvider.notifier)
                      .selectActiveBot(bot.id);
                  if (!ok || !mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CareWorkspacePage(initialTab: 0),
                    ),
                  );
                },
              ),
              if (!bot.isChief && !bot.isPrivate)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    '删除 ${bot.name}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final ok = await showCareConfirmDialog(
                      context,
                      title: '删除「${bot.name}」？',
                      message: '该 Bot 的对话记录将被清除，公共记忆不受影响。',
                      confirmLabel: '删除',
                      destructive: true,
                    );
                    if (ok) {
                      ref.read(careChatProvider.notifier).purgeBotThread(bot.id);
                      await ref
                          .read(careBotsProvider.notifier)
                          .deleteSpecialist(bot.id);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openQuickHub() async {
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.wb_sunny_outlined),
                title: const Text('今日'),
                subtitle: const Text('简报、提醒、日程与通知摘要'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const CareTodayPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.auto_stories_outlined),
                title: const Text('记忆与性格'),
                subtitle: const Text('查看或编辑 MEMORY.md 与 SOUL.md'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CareMemoryPage(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('定时任务与自动化'),
                subtitle: const Text('跨应用操作与定时任务管理'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CareAutomationPage(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('设置'),
                subtitle: const Text('API Key、模型、外观与本地加密备份'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CareSettingsPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatHubTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return careClockTime(dt);
    if (diff == 1) return '昨天';
    if (diff > 1 && diff < 7) {
      const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
      return weekdays[dt.weekday - 1];
    }
    return '${dt.month}月${dt.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final botsAsync = ref.watch(careBotsProvider);
    final summaries = ref.watch(
      careChatProvider.select((s) => s.threadSummaries),
    );
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final pullProgress = (_pullUpOverscroll / _kPrivacyTriggerPx).clamp(0.0, 1.0);

    return CareAtmosphereBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: CareContentWidth(
            child: botsAsync.when(
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: FilledButton(
                  onPressed: () => ref.invalidate(careBotsProvider),
                  child: const Text('重试'),
                ),
              ),
              data: (botsState) {
                final chief = botsState.chiefBot;
                final chiefSummary = summaries[chief.id];
                final q = _query.trim().toLowerCase();

                // Discreet search unlock: typing `privacy` / `隐私` reveals Privacy Bot row.
                final revealPrivacyBySearch =
                    q.isNotEmpty && (q.contains('privacy') || q.contains('隐私'));

                // Specialist bots ONLY (Chief Bot is fixed at top hero; Privacy Bot is hidden!).
                final visibleBots = <CareBotProfile>[
                  if (q.isNotEmpty) chief,
                  ...botsState.specialists,
                  if (revealPrivacyBySearch) botsState.privacyBot,
                ].where((b) {
                  if (q.isEmpty) return true;
                  if (b.isPrivate && revealPrivacyBySearch) return true;
                  final preview = summaries[b.id]?.lastPreview.toLowerCase() ?? '';
                  return b.name.toLowerCase().contains(q) ||
                      b.roleTitle.toLowerCase().contains(q) ||
                      preview.contains(q);
                }).toList();

                return Column(
                  children: [
                    // ── Top floating circle actions (Settings & + Create Bot) ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                      child: Row(
                        children: [
                          _CircleAction(
                            tooltip: '设置',
                            icon: Icons.settings_outlined,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const CareSettingsPage(),
                              ),
                            ),
                          ),
                          const Spacer(),
                          _CircleAction(
                            tooltip: '新建 Bot',
                            icon: Icons.add_rounded,
                            onTap: _createBot,
                          ),
                        ],
                      ),
                    ),

                    // ── Scrollable Hero + Specialist List + Elastic Pull-Up Privacy Reveal ──
                    Expanded(
                      child: Stack(
                        children: [
                          NotificationListener<ScrollNotification>(
                            onNotification: (n) =>
                                _onScrollNotification(n, botsState.privacyBot),
                            child: ListView(
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 44),
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              children: [
                                if (q.isEmpty) ...[
                                  Center(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _enterBot(chief),
                                      onLongPress: () => _openBotActions(chief),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 4,
                                        ),
                                        child: Column(
                                          children: [
                                            Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                CareBotAvatar.forBot(
                                                  chief,
                                                  size: 94,
                                                  interactive: false,
                                                ),
                                                Positioned(
                                                  right: 0,
                                                  bottom: 2,
                                                  child: Container(
                                                    width: 26,
                                                    height: 26,
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFFFA726),
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: isLight
                                                            ? Colors.white
                                                            : scheme.surface,
                                                        width: 2.5,
                                                      ),
                                                    ),
                                                    child: const Icon(
                                                      Icons.star_rounded,
                                                      size: 15,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              chief.name,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: scheme.onSurface,
                                              ),
                                            ),
                                            if (chiefSummary != null) ...[
                                              const SizedBox(height: 4),
                                              ConstrainedBox(
                                                constraints: const BoxConstraints(
                                                  maxWidth: 260,
                                                ),
                                                child: Text(
                                                  chiefSummary.lastPreview,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: theme.textTheme.bodySmall
                                                      ?.copyWith(
                                                    color: scheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                ],
                                for (final bot in visibleBots)
                                  _BotConversationRow(
                                    key: ValueKey('hub-${bot.id}'),
                                    bot: bot,
                                    summary: bot.isPrivate ? null : summaries[bot.id],
                                    privacyUnlocked: botsState.privacyUnlocked,
                                    timeLabel: !bot.isPrivate &&
                                            summaries[bot.id] != null
                                        ? _formatHubTime(
                                            summaries[bot.id]!.lastMessageAt,
                                          )
                                        : null,
                                    onTap: () => _enterBot(bot),
                                    onLongPress: () => _openBotActions(bot),
                                  ),
                                if (botsState.specialists.isEmpty && q.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 18),
                                    child: Center(
                                      child: TextButton.icon(
                                        onPressed: _createBot,
                                        icon: const Icon(Icons.add_rounded,
                                            size: 18),
                                        label: const Text('新建专职 Bot（如 Study / Finance）'),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // ── Elastic Pull-Up Reveal Capsule for Privacy Bot ──
                          if (pullProgress > 0.06)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 8,
                              child: IgnorePointer(
                                child: Center(
                                  child: Opacity(
                                    opacity: pullProgress.clamp(0.0, 1.0),
                                    child: Transform.translate(
                                      offset: Offset(
                                        0,
                                        (1.0 - pullProgress) * 26.0,
                                      ),
                                      child: Transform.scale(
                                        scale: 0.86 + pullProgress * 0.14,
                                        child: _PrivacyPullRevealPill(
                                          progress: pullProgress,
                                          armed: _privacyArmed,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // ── Bottom Dock: Quick Tools Grid + Pill Search Bar ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Row(
                        children: [
                          _CircleAction(
                            tooltip: '功能菜单',
                            icon: Icons.grid_view_rounded,
                            onTap: _openQuickHub,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: isLight
                                    ? Colors.white.withValues(alpha: 0.94)
                                    : scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(
                                  color: scheme.outlineVariant
                                      .withValues(alpha: 0.7),
                                ),
                                boxShadow: isLight
                                    ? [
                                        BoxShadow(
                                          color: scheme.primary
                                              .withValues(alpha: 0.05),
                                          blurRadius: 12,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: TextField(
                                controller: _searchCtrl,
                                onChanged: (v) => setState(() => _query = v),
                                textAlignVertical: TextAlignVertical.center,
                                decoration: InputDecoration(
                                  hintText: '搜索 Bot 或聊天记录',
                                  prefixIcon: Icon(
                                    Icons.search_rounded,
                                    color: scheme.onSurfaceVariant,
                                    size: 21,
                                  ),
                                  suffixIcon: _query.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.close_rounded,
                                              size: 18),
                                          onPressed: () {
                                            _searchCtrl.clear();
                                            setState(() => _query = '');
                                          },
                                        )
                                      : null,
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyPullRevealPill extends StatelessWidget {
  const _PrivacyPullRevealPill({
    required this.progress,
    required this.armed,
  });

  final double progress;
  final bool armed;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: armed ? const Color(0xFF1F2752) : const Color(0xE8161C36),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: armed
              ? const Color(0xFF9EA8FF)
              : const Color(0xFF9EA8FF).withValues(alpha: 0.35),
          width: armed ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0E1324).withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2.2,
                  color: const Color(0xFF9EA8FF),
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                ),
                Icon(
                  armed ? Icons.fingerprint_rounded : Icons.lock_outline_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Text(
              armed ? '松手解锁 Privacy Bot' : '继续上拉 · Privacy Bot',
              key: ValueKey(armed),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    return Material(
      color: isLight
          ? Colors.white.withValues(alpha: 0.94)
          : scheme.surfaceContainerHigh,
      shape: CircleBorder(
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      elevation: isLight ? 1 : 0,
      shadowColor: scheme.primary.withValues(alpha: 0.12),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 22, color: scheme.onSurface),
          ),
        ),
      ),
    );
  }
}

class _BotConversationRow extends StatelessWidget {
  const _BotConversationRow({
    super.key,
    required this.bot,
    required this.summary,
    required this.privacyUnlocked,
    required this.timeLabel,
    required this.onTap,
    required this.onLongPress,
  });

  final CareBotProfile bot;
  final CareBotThreadSummary? summary;
  final bool privacyUnlocked;
  final String? timeLabel;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preview = bot.isPrivate
        ? (privacyUnlocked ? '已解锁 · 点击进入私密对话' : '独立隔离 · 点击指纹/锁屏解锁')
        : (summary?.lastPreview ?? bot.roleTitle);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
        child: Row(
          children: [
            CareBotAvatar.forBot(bot, size: 46, interactive: false),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          bot.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (bot.isPrivate) ...[
                        const SizedBox(width: 5),
                        Icon(
                          privacyUnlocked
                              ? Icons.lock_open_rounded
                              : Icons.lock_outline_rounded,
                          size: 15,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (timeLabel != null)
                  Text(
                    timeLabel!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (summary?.unread == true) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
