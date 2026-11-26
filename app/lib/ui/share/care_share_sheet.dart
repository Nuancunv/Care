import 'dart:async';

import 'package:care_app/services/care_share_bridge.dart';
import 'package:care_app/services/care_workspace_bridge.dart';
import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../chat/care_chat_page.dart';
import '../common/care_bot_avatar.dart';
import '../common/care_copy.dart';
import '../common/care_widgets.dart';

/// Listens for Android system Share Intents (`ACTION_SEND`) and presents a sleek
/// target-Bot chooser sheet so users can either save shared content straight
/// into any Bot's `资料库/` or immediately ask that Bot about it.
class CareShareListener extends ConsumerStatefulWidget {
  const CareShareListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CareShareListener> createState() => _CareShareListenerState();
}

class _CareShareListenerState extends ConsumerState<CareShareListener> {
  StreamSubscription<CareSharedItem>? _sub;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_attach);
  }

  Future<void> _attach() async {
    if (!mounted) return;
    final platform = ref.read(careSharePlatformProvider);
    _sub = platform.shareEvents().listen(_handleShare, onError: (_) {});
    final initial = await platform.takePendingShare();
    if (initial != null && mounted) {
      _handleShare(initial);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _handleShare(CareSharedItem item) async {
    if (!mounted || _sheetOpen) return;
    final hasKey = ref.read(careSettingsProvider).value?.hasApiKey ?? false;
    if (!hasKey) return;

    _sheetOpen = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _CareShareTargetSheet(item: item),
      );
    } finally {
      _sheetOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _CareShareTargetSheet extends ConsumerStatefulWidget {
  const _CareShareTargetSheet({required this.item});

  final CareSharedItem item;

  @override
  ConsumerState<_CareShareTargetSheet> createState() =>
      _CareShareTargetSheetState();
}

class _CareShareTargetSheetState extends ConsumerState<_CareShareTargetSheet> {
  String _selectedBotId = kCareChiefBotId;
  bool _busy = false;

  Future<void> _saveToLibrary(CareBotProfile target) async {
    setState(() => _busy = true);
    try {
      final item = widget.item;
      if (item.hasFile) {
        await ref
            .read(careWorkspaceProvider.notifier)
            .importStagedToBotLibrary(
              botId: target.id,
              isPrivate: false,
              stagedPath: item.stagedPath,
              fileName: item.fileName,
            );
      } else {
        final now = DateTime.now();
        final name =
            '分享_${careTwoDigits(now.month)}${careTwoDigits(now.day)}_${careTwoDigits(now.hour)}${careTwoDigits(now.minute)}${careTwoDigits(now.second)}.md';
        final header = item.subject.isNotEmpty ? '# ${item.subject}\n\n' : '';
        await ref.read(careWorkspacePlatformProvider).writeFile(
              botId: target.id,
              isPrivate: false,
              path: '$kCareLibraryFolder/$name',
              content: '$header${item.text}',
            );
        await ref.read(careWorkspaceProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showCareSnack(context, '已存入「${target.name}」资料库');
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showCareSnack(context, '存入资料库失败，请稍后再试。');
      }
    }
  }

  Future<void> _sendToChat(CareBotProfile target) async {
    setState(() => _busy = true);
    try {
      final ok =
          await ref.read(careBotsProvider.notifier).selectActiveBot(target.id);
      if (!ok || !mounted) return;
      ref
          .read(careChatProvider.notifier)
          .syncActiveBot(target.id, profile: target);

      final item = widget.item;
      final att = item.toAttachment();
      final prompt = item.text.isNotEmpty
          ? (item.subject.isNotEmpty ? '${item.subject}\n${item.text}' : item.text)
          : '请帮我分析这份分享的内容：${item.fileName}';

      final nav = Navigator.of(context);
      final chat = ref.read(careChatProvider.notifier);
      nav.pop();
      unawaited(
        nav.push(
          MaterialPageRoute<void>(builder: (_) => const CareChatPage()),
        ),
      );
      unawaited(
        chat.sendMessage(
          prompt,
          attachments: att != null ? [att] : const [],
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showCareSnack(context, '发送失败，请稍后再试。');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final botsState = ref.watch(careBotsProvider).value;
    final bots = <CareBotProfile>[
      botsState?.chiefBot ?? kChiefBotProfile,
      ...?botsState?.specialists,
    ];
    final target = bots.firstWhere(
      (b) => b.id == _selectedBotId,
      orElse: () => bots.first,
    );
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '收到分享内容',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.item.isImage
                        ? Icons.image_outlined
                        : widget.item.hasFile
                            ? Icons.insert_drive_file_outlined
                            : Icons.link_rounded,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.item.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '选择目标 Bot',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final bot in bots)
                  ChoiceChip(
                    avatar: CareBotAvatar.forBot(
                      bot,
                      size: 20,
                      interactive: false,
                    ),
                    label: Text(bot.name),
                    selected: bot.id == target.id,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _selectedBotId = bot.id),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _saveToLibrary(target),
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('存入资料库'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _sendToChat(target),
                    icon: const Icon(Icons.send_rounded, size: 17),
                    label: const Text('发给它聊'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
