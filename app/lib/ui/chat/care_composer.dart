import 'dart:convert';

import 'package:care_app/services/care_workspace_bridge.dart';
import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../common/care_bot_avatar.dart';
import '../common/care_copy.dart';
import '../common/care_widgets.dart';
import 'care_model_sheet.dart';

/// Today-inspired floating message composer with:
/// - 3-way `+` attachment picker (`选择文件` / `拍照` / `照片`)
/// - `@Bot` live mention bar for multi-Bot collaboration
/// - Per-Bot Model + Thinking Effort selector
///
/// Subscribes only to `isStreaming` and Bot metadata (never streaming deltas).
/// Per ADR-002 the first release has NO microphone / voice entry.
class CareComposer extends ConsumerStatefulWidget {
  const CareComposer({super.key});

  @override
  ConsumerState<CareComposer> createState() => _CareComposerState();
}

class _CareComposerState extends ConsumerState<CareComposer> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final List<CarePickedAttachment> _attachments = [];
  bool _hasText = false;
  String? _mentionQuery;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _ctrl.text;
    final has = text.trim().isNotEmpty;
    final mq = _extractMentionQuery(text, _ctrl.selection.baseOffset);
    if (has != _hasText || mq != _mentionQuery) {
      setState(() {
        _hasText = has;
        _mentionQuery = mq;
      });
    }
  }

  static String? _extractMentionQuery(String text, int cursor) {
    final end = (cursor >= 0 && cursor <= text.length) ? cursor : text.length;
    final before = text.substring(0, end);
    final match = RegExp(r'(?:^|\s)@([^\s@]{0,20})$').firstMatch(before);
    return match?.group(1);
  }

  void _insertMention(CareBotProfile bot) {
    final text = _ctrl.text;
    final end = (_ctrl.selection.baseOffset >= 0 &&
            _ctrl.selection.baseOffset <= text.length)
        ? _ctrl.selection.baseOffset
        : text.length;
    final before = text.substring(0, end);
    final after = text.substring(end);
    final atIdx = before.lastIndexOf('@');
    if (atIdx < 0) return;
    final replaced = '${before.substring(0, atIdx)}@${bot.name} $after';
    final nextOffset = atIdx + bot.name.length + 2;
    _ctrl.value = TextEditingValue(
      text: replaced,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _focus.requestFocus();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    final pending = List<CarePickedAttachment>.from(_attachments);
    _ctrl.clear();
    setState(() {
      _attachments.clear();
      _mentionQuery = null;
    });
    ref.read(careChatProvider.notifier).sendMessage(text, attachments: pending);
  }

  Future<void> _pick(String mode) async {
    try {
      final item = await ref
          .read(careWorkspacePlatformProvider)
          .pickAttachment(mode: mode);
      if (item == null || !mounted) return;
      setState(() => _attachments.add(item));
    } catch (_) {
      if (mounted) showCareSnack(context, '读取文件失败，请稍后再试。');
    }
  }

  Future<void> _openAttachMenu() async {
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: const Text('选择文件'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pick('file');
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('拍照'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pick('camera');
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('照片'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pick('photo');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isStreaming = ref.watch(careChatProvider.select((s) => s.isStreaming));
    final botsState = ref.watch(careBotsProvider).value;
    final activeBot = botsState?.activeBot ?? kChiefBotProfile;
    final (chiefModel, chiefEffort) = ref.watch(
      careSettingsProvider.select(
        (s) => (
          s.value?.activeModel ?? kCareDefaultModel,
          s.value?.activeEffort ?? kCareDefaultEffort,
        ),
      ),
    );
    final effectiveModel =
        activeBot.isChief ? chiefModel : activeBot.preferredModel;
    final effectiveEffort =
        activeBot.isChief ? chiefEffort : activeBot.preferredEffort;

    // Mention candidates (strictly disabled inside Privacy Bot for physical isolation).
    final mentionCandidates = <CareBotProfile>[];
    if (_mentionQuery != null && !activeBot.isPrivate && botsState != null) {
      final q = _mentionQuery!.toLowerCase();
      for (final b in [botsState.chiefBot, ...botsState.specialists]) {
        if (b.id == activeBot.id) continue;
        if (q.isEmpty || b.name.toLowerCase().contains(q)) {
          mentionCandidates.add(b);
        }
      }
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final canSend = isStreaming || _hasText || _attachments.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── @Bot Live Mention Bar ──
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: mentionCandidates.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: mentionCandidates.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final target = mentionCandidates[i];
                          return ActionChip(
                            avatar: CareBotAvatar.forBot(
                              target,
                              size: 20,
                              interactive: false,
                            ),
                            label: Text('@${target.name}'),
                            shape: const StadiumBorder(),
                            backgroundColor: isLight
                                ? Colors.white
                                : scheme.surfaceContainerHigh,
                            side: BorderSide(
                              color: scheme.primary.withValues(alpha: 0.35),
                            ),
                            onPressed: () => _insertMention(target),
                          );
                        },
                      ),
                    ),
                  ),
          ),
          Container(
            decoration: BoxDecoration(
              color: isLight
                  ? Colors.white.withValues(alpha: 0.96)
                  : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.8),
              ),
              boxShadow: isLight
                  ? [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                    child: SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _attachments.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final att = _attachments[i];
                          return InputChip(
                            avatar: att.isImage && att.base64Image.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.memory(
                                      base64Decode(att.base64Image),
                                      width: 24,
                                      height: 24,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.image_outlined,
                                        size: 16,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.description_outlined,
                                    size: 16),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: Text(
                                att.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            shape: const StadiumBorder(),
                            onDeleted: isStreaming
                                ? null
                                : () => setState(() => _attachments.removeAt(i)),
                          );
                        },
                      ),
                    ),
                  ),
                TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: activeBot.isPrivate
                        ? '给 Privacy Bot 发消息（隔离加密）'
                        : '给 ${activeBot.name} 发消息（可 @ 其他 Bot）',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: '添加图片或文件',
                      onPressed: isStreaming ? null : _openAttachMenu,
                      icon: Icon(
                        Icons.add_circle_outline_rounded,
                        color: scheme.primary,
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(100),
                      onTap: isStreaming
                          ? null
                          : () => showCareModelEffortSheet(
                                context,
                                bot: activeBot,
                              ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${careModelShortLabel(effectiveModel)} · ${careEffortShortLabel(effectiveEffort)}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: scheme.onPrimaryContainer,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Reserved slot: future voice input (deferred by ADR-002).
                    _SendButton(
                      streaming: isStreaming,
                      enabled: canSend,
                      onSend: _send,
                      onStop: () =>
                          ref.read(careChatProvider.notifier).stopStreaming(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.streaming,
    required this.enabled,
    required this.onSend,
    required this.onStop,
  });

  final bool streaming;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: streaming ? '停止回复' : '发送',
      onPressed: enabled ? (streaming ? onStop : onSend) : null,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: Icon(
          streaming ? Icons.stop_rounded : Icons.arrow_upward_rounded,
          key: ValueKey(streaming),
        ),
      ),
    );
  }
}
