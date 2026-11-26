import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../automation/care_automation_page.dart';
import '../bots/care_bots_page.dart';
import '../care_theme.dart';
import '../common/care_bot_avatar.dart';
import '../common/care_copy.dart';
import '../common/care_widgets.dart';
import '../memory/care_memory_page.dart';
import '../settings/care_settings_page.dart';
import '../today/care_today_page.dart';
import '../workspace/care_workspace_page.dart';
import 'care_chat_timeline.dart';
import 'care_composer.dart';
import 'care_model_sheet.dart';

/// Care's per-Bot conversation screen.
///
/// Streaming performance contract (AGENTS.md §3.1): this outer page only selects
/// `(isStreaming, error, backend)` and `isPrivate` so per-token deltas NEVER
/// rebuild the page, app bar, or composer.
class CareChatPage extends ConsumerWidget {
  const CareChatPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (isStreaming, error, backend) = ref.watch(
      careChatProvider.select((s) => (s.isStreaming, s.error, s.backend)),
    );
    final isPrivate = ref.watch(
      careBotsProvider.select((s) => s.value?.activeBot.isPrivate ?? false),
    );

    final scaffold = CareAtmosphereBackground(
      stealth: isPrivate,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          titleSpacing: 8,
          title: _ActiveBotHeader(isStreaming: isStreaming, backend: backend),
          actions: [
            if (isPrivate) ...[
              IconButton(
                tooltip: '私密笔记',
                icon: const Icon(Icons.edit_note_rounded),
                onPressed: () => showCarePrivacyNotesSheet(context),
              ),
              IconButton(
                tooltip: '立即上锁',
                icon: const Icon(Icons.lock_outline_rounded),
                onPressed: () {
                  ref.read(careBotsProvider.notifier).lockPrivacyVault();
                  ref
                      .read(careChatProvider.notifier)
                      .purgeBotThread(kCarePrivacyBotId);
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                  showCareSnack(context, 'Privacy Bot 已上锁并清空内存');
                },
              ),
            ] else ...[
              IconButton(
                tooltip: '资料库',
                icon: const Icon(Icons.menu_book_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CareWorkspacePage(initialTab: 0),
                  ),
                ),
              ),
              IconButton(
                tooltip: '工作空间',
                icon: const Icon(Icons.folder_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CareWorkspacePage(initialTab: 1),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (value) => _onMenu(context, ref, value, isStreaming),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'today',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.wb_sunny_outlined),
                      title: Text('今日'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'memory',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.auto_stories_outlined),
                      title: Text('记忆与性格'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'automation',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.schedule_rounded),
                      title: Text('定时任务与自动化'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'clear',
                    enabled: !isStreaming,
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.cleaning_services_outlined),
                      title: Text('清空对话'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'settings',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.settings_outlined),
                      title: Text('设置'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          top: false,
          child: CareContentWidth(
            child: Column(
              children: [
                const Expanded(child: CareChatTimeline()),
                if (error != null && !isStreaming) _ChatErrorBanner(error: error),
                const CareComposer(),
              ],
            ),
          ),
        ),
      ),
    );

    if (isPrivate) {
      return Theme(data: CareTheme.privacyDark(), child: scaffold);
    }
    return scaffold;
  }

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    String value,
    bool isStreaming,
  ) async {
    switch (value) {
      case 'today':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CareTodayPage()),
        );
      case 'memory':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CareMemoryPage()),
        );
      case 'automation':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CareAutomationPage()),
        );
      case 'clear':
        if (isStreaming) return;
        final ok = await showCareConfirmDialog(
          context,
          title: '清空对话？',
          message: '当前屏幕上的聊天记录将被清除。Care 的长期记忆不受影响。',
          confirmLabel: '清空',
          destructive: true,
        );
        if (ok) ref.read(careChatProvider.notifier).clearThread();
      case 'settings':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CareSettingsPage()),
        );
    }
  }
}

/// Isolated AppBar header leaf; tapping opens this Bot's model & thinking sheet.
class _ActiveBotHeader extends ConsumerWidget {
  const _ActiveBotHeader({required this.isStreaming, required this.backend});

  final bool isStreaming;
  final CareChatBackend backend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBot = ref.watch(
      careBotsProvider.select((s) => s.value?.activeBot ?? kChiefBotProfile),
    );
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitle = isStreaming
        ? '正在输入…'
        : activeBot.isPrivate
            ? '物理隔离 · 切后台自动上锁'
            : !activeBot.isChief
                ? activeBot.roleTitle
                : backend == CareChatBackend.localEngine
                    ? '在线 · 本机 Bot'
                    : '在线';

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showCareModelEffortSheet(context, bot: activeBot),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CareBotAvatar.forBot(
              activeBot,
              size: 36,
              active: isStreaming,
              interactive: false,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          activeBot.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (activeBot.isPrivate) ...[
                        const SizedBox(width: 5),
                        Icon(Icons.shield_outlined,
                            size: 15, color: scheme.primary),
                      ],
                    ],
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: activeBot.isPrivate
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatErrorBanner extends StatefulWidget {
  const _ChatErrorBanner({required this.error});

  final String error;

  @override
  State<_ChatErrorBanner> createState() => _ChatErrorBannerState();
}

class _ChatErrorBannerState extends State<_ChatErrorBanner> {
  String? _dismissed;

  @override
  Widget build(BuildContext context) {
    if (_dismissed == widget.error) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final needsSettings = careErrorNeedsSettings(widget.error);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              careFriendlyError(widget.error),
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          if (needsSettings)
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const CareSettingsPage()),
              ),
              child: const Text('去设置'),
            ),
          IconButton(
            tooltip: '关闭',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 18, color: scheme.onErrorContainer),
            onPressed: () => setState(() => _dismissed = widget.error),
          ),
        ],
      ),
    );
  }
}
