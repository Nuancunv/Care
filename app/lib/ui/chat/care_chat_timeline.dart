import 'dart:convert';

import 'package:care_app/services/care_workspace_bridge.dart';
import 'package:care_app/state/care_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../common/care_bot_avatar.dart';
import '../common/care_copy.dart';
import '../common/care_markdown_view.dart';
import '../common/care_widgets.dart';
import '../workspace/care_workspace_page.dart';

/// Scrollable conversation timeline.
///
/// Uses a top-to-bottom [CustomScrollView] so that when a user sends a prompt
/// and Care begins answering, the viewport scrolls ONCE to keep the first line
/// of the reply calmly in view — never force-scrolling to the bottom as a long
/// answer streams in.
class CareChatTimeline extends ConsumerStatefulWidget {
  const CareChatTimeline({super.key});

  @override
  ConsumerState<CareChatTimeline> createState() => _CareChatTimelineState();
}

class _CareChatTimelineState extends ConsumerState<CareChatTimeline> {
  final _scroll = ScrollController();
  bool _showJumpToBottom = false;
  int _lastMsgCount = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _lastMsgCount = ref.read(careChatProvider).messages.length;
    if (_lastMsgCount > 0) {
      _jumpToLatestOnOpen();
    }
  }

  void _jumpToLatestOnOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      // Settle once more after Markdown / code blocks finish initial layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final max = _scroll.position.maxScrollExtent;
        if ((max - _scroll.position.pixels) > 4) {
          _scroll.jumpTo(max);
        }
      });
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final away = (pos.maxScrollExtent - pos.pixels) > 220;
    if (away != _showJumpToBottom) {
      setState(() => _showJumpToBottom = away);
    }
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = ref.watch(
      careChatProvider.select((s) => s.messages.isEmpty && !s.isStreaming),
    );

    // Scroll ONCE when returning to a hydrated thread or when the user sends a
    // new message so the start (line 1) of Care's reply stays calmly in view
    // without auto-scrolling away while streaming.
    ref.listen<int>(
      careChatProvider.select((s) => s.messages.length),
      (_, nextLen) {
        if (_lastMsgCount == 0 &&
            nextLen > 0 &&
            !ref.read(careChatProvider).isStreaming) {
          _jumpToLatestOnOpen();
        } else if (nextLen > _lastMsgCount) {
          final msgs = ref.read(careChatProvider).messages;
          if (msgs.isNotEmpty && msgs.last.role == CareMessageRole.user) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scroll.hasClients) {
                _scroll.animateTo(
                  _scroll.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                );
              }
            });
          }
        }
        _lastMsgCount = nextLen;
      },
    );

    if (isEmpty) return const _EmptyGreeting();

    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        CustomScrollView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: const [
            SliverToBoxAdapter(child: SizedBox(height: 8)),
            _MessagesSliver(),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverToBoxAdapter(child: CareDraftBubble()),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 12,
          child: AnimatedScale(
            scale: _showJumpToBottom ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: IgnorePointer(
              ignoring: !_showJumpToBottom,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.surfaceContainerLow,
                  foregroundColor: scheme.onSurface,
                  minimumSize: const Size(40, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _jumpToBottom,
                icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                label: const Text('查看底部'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Committed history. Only rebuilds when a message is committed or cleared.
class _MessagesSliver extends ConsumerWidget {
  const _MessagesSliver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(careChatProvider.select((s) => s.messages));
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverList.builder(
        itemCount: messages.length,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<String>) return null;
          final idx = messages.indexWhere((m) => m.id == key.value);
          return idx < 0 ? null : idx;
        },
        itemBuilder: (context, i) {
          final m = messages[i];
          return CareMessageRow(key: ValueKey<String>(m.id), message: m);
        },
      ),
    );
  }
}

/// The in-flight assistant reply. This is the ONLY widget that rebuilds on
/// per-token `draftText` / `draftReasoning` deltas.
class CareDraftBubble extends ConsumerWidget {
  const CareDraftBubble({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (streaming, text, reasoning, tools) = ref.watch(
      careChatProvider.select(
        (s) => (
          s.isStreaming,
          s.draftText,
          s.draftReasoning,
          s.draftToolActivities,
        ),
      ),
    );
    if (!streaming) return const SizedBox.shrink();
    if (text.isEmpty && reasoning.isEmpty && tools.isEmpty) {
      return const _AssistantFrame(streaming: true, child: _TypingDots());
    }
    return _AssistantFrame(
      streaming: true,
      child: _AssistantContent(
        content: text,
        reasoning: reasoning,
        toolActivities: tools,
        streaming: true,
      ),
    );
  }
}

class CareMessageRow extends StatelessWidget {
  const CareMessageRow({super.key, required this.message});

  final CareChatMessage message;

  @override
  Widget build(BuildContext context) {
    return switch (message.role) {
      CareMessageRole.user => _UserBubble(message: message),
      CareMessageRole.assistant => _AssistantFrame(
          streaming: false,
          child: _AssistantContent(
            content: message.content,
            reasoning: message.reasoning,
            toolActivities: message.toolActivities,
            streaming: false,
            createdAt: message.createdAt,
          ),
        ),
      CareMessageRole.system => _SystemNote(text: message.content),
    };
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});

  final CareChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.78;
    return Padding(
      padding: const EdgeInsets.only(top: 14, left: 48),
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onLongPress: () => _copy(context, message.content),
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.attachments.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final att in message.attachments)
                        _UserAttachmentBadge(att: att),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  message.content,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: scheme.onPrimary, height: 1.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserAttachmentBadge extends StatelessWidget {
  const _UserAttachmentBadge({required this.att});

  final CarePickedAttachment att;

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    if (att.isImage && att.base64Image.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          base64Decode(att.base64Image),
          width: 140,
          height: 100,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Icon(Icons.image_outlined, color: onPrimary),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 14, color: onPrimary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              att.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: onPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantFrame extends ConsumerWidget {
  const _AssistantFrame({required this.streaming, required this.child});

  final bool streaming;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBot = ref.watch(
      careBotsProvider.select((s) => s.value?.activeBot ?? kChiefBotProfile),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 14, right: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: CareBotAvatar.forBot(
              activeBot,
              size: 30,
              active: streaming,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(child: child),
        ],
      ),
    );
  }
}

class _AssistantContent extends ConsumerWidget {
  const _AssistantContent({
    required this.content,
    required this.reasoning,
    required this.toolActivities,
    required this.streaming,
    this.createdAt,
  });

  final String content;
  final String reasoning;
  final List<CareToolActivity> toolActivities;
  final bool streaming;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final fileCards = toolActivities
        .where((a) => a.workspacePath != null && a.workspacePath!.isNotEmpty)
        .toList();
    final otherTools = toolActivities
        .where((a) => a.workspacePath == null || a.workspacePath!.isEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reasoning.isNotEmpty)
          _ReasoningPanel(
            reasoning: reasoning,
            thinking: streaming && content.isEmpty,
          ),
        if (otherTools.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final act in otherTools)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isLight
                          ? Colors.white.withValues(alpha: 0.92)
                          : scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          act.ok
                              ? Icons.check_circle_outline_rounded
                              : Icons.shield_outlined,
                          size: 15,
                          color: act.ok ? scheme.primary : scheme.error,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            act.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (content.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isLight ? Colors.white : scheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              border: Border.all(
                color: scheme.outlineVariant
                    .withValues(alpha: isLight ? 0.65 : 0.4),
              ),
            ),
            child: SelectionArea(
              child: CareMarkdownView(markdown: content),
            ),
          ),
        if (fileCards.isNotEmpty) ...[
          if (content.isNotEmpty) const SizedBox(height: 8),
          for (final fc in fileCards)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _InlineWorkspaceFileCard(path: fc.workspacePath!),
            ),
        ],
        if (!streaming && content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '复制',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  color: scheme.onSurfaceVariant,
                  onPressed: () => _copy(context, content),
                  icon: const Icon(Icons.content_copy_rounded),
                ),
                if (createdAt != null)
                  Text(
                    careClockTime(createdAt!),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _InlineWorkspaceFileCard extends ConsumerWidget {
  const _InlineWorkspaceFileCard({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isHtml = careIsHtmlPath(path);
    final isPrivate = ref.watch(
      careWorkspaceProvider.select((s) => s.value?.isPrivate ?? false),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    careWorkspaceFileIcon(path),
                    size: 20,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        careWorkspaceFileTypeLabel(path),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: () => showCareWorkspaceFileSheet(
                    context,
                    ref,
                    path,
                    preferRenderedHtml: isHtml,
                  ),
                  icon: Icon(
                    isHtml ? Icons.language_rounded : Icons.visibility_outlined,
                    size: 17,
                  ),
                  label: Text(isHtml ? '渲染网页' : '打开预览'),
                ),
                if (isHtml)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(56, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () => showCareWorkspaceFileSheet(
                      context,
                      ref,
                      path,
                      preferRenderedHtml: false,
                    ),
                    child: const Text('看源码'),
                  ),
                if (!isPrivate)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(56, 36),
                    ),
                    onPressed: () async {
                      final ok = await ref
                          .read(careWorkspaceProvider.notifier)
                          .openWithExternalApp(path);
                      if (!ok && context.mounted) {
                        showCareSnack(context, '未找到可打开此文件的默认应用');
                      }
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('默认应用打开'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Collapsed-by-default thinking summary pill.
/// Shows calm concise cues ("正在思考…" / "琢磨一下…" / "思考过程") and expands
/// only when the user explicitly taps the chevron.
class _ReasoningPanel extends StatefulWidget {
  const _ReasoningPanel({required this.reasoning, required this.thinking});

  final String reasoning;
  final bool thinking;

  @override
  State<_ReasoningPanel> createState() => _ReasoningPanelState();
}

class _ReasoningPanelState extends State<_ReasoningPanel> {
  static const _phrases = ['正在思考…', '琢磨一下…', '整理思路中…'];
  bool _expanded = false;

  String get _statusLabel {
    if (!widget.thinking) return '思考过程';
    final idx = (widget.reasoning.length ~/ 60) % _phrases.length;
    return _phrases[idx];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(100),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 15,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _statusLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: scheme.onPrimaryContainer,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              margin: const EdgeInsets.only(left: 10, top: 6),
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: scheme.primary.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
              ),
              child: SelectableText(
                widget.reasoning,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.55,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SystemNote extends StatelessWidget {
  const _SystemNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : scheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(6),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: isLight ? 0.65 : 0.4),
        ),
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_ctrl.value - i * 0.18) % 1.0;
            final lift = t < 0.5 ? t * 2 : (1 - t) * 2;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Opacity(
                opacity: 0.35 + 0.65 * lift,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _EmptyGreeting extends ConsumerWidget {
  const _EmptyGreeting();

  static const _suggestions = <(IconData, String)>[
    (Icons.today_outlined, '帮我规划一下今天的安排'),
    (Icons.code_rounded, '在工作空间写一个待办清单网页'),
    (Icons.bookmark_add_outlined, '记住：我对花生过敏'),
    (Icons.lightbulb_outline_rounded, '用三句话讲清楚什么是复利'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBot = ref.watch(
      careBotsProvider.select((s) => s.value?.activeBot ?? kChiefBotProfile),
    );
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CareBotAvatar.forBot(activeBot, size: 74),
              const SizedBox(height: 18),
              Text(
                activeBot.isChief
                    ? '有什么我可以帮你的？'
                    : '你好，我是${activeBot.name}',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                activeBot.isChief
                    ? '聊天、记事、写代码文档，都可以直接说。'
                    : activeBot.roleTitle,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 26),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (icon, text) in _suggestions)
                    ActionChip(
                      avatar: Icon(icon, size: 17, color: scheme.primary),
                      label: Text(text),
                      shape: const StadiumBorder(),
                      side: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.75),
                      ),
                      backgroundColor:
                          isLight ? Colors.white.withValues(alpha: 0.92) : scheme.surfaceContainerLow,
                      onPressed: () =>
                          ref.read(careChatProvider.notifier).sendMessage(text),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _copy(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showCareSnack(context, '已复制');
}
