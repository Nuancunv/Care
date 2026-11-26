import 'package:care_app/state/care_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../common/care_copy.dart';
import '../common/care_markdown_view.dart';
import '../common/care_widgets.dart';

enum _DocKind { memory, soul }

/// Transparent memory & personality center for plain-Markdown `MEMORY.md` and
/// `SOUL.md` (AGENTS.md §3.3): readable, editable, exportable at any time.
class CareMemoryPage extends ConsumerWidget {
  const CareMemoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(careMemoryProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('记忆与性格'),
          actions: [
            PopupMenuButton<String>(
              tooltip: '更多',
              enabled: memory.hasValue,
              onSelected: (v) => _onMenu(context, ref, v),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'reset',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.restore_rounded),
                    title: Text('恢复默认'),
                  ),
                ),
              ],
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '我的记忆'),
              Tab(text: 'Care 的性格'),
            ],
          ),
        ),
        body: memory.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _LoadError(
            onRetry: () => ref.invalidate(careMemoryProvider),
          ),
          data: (_) => const TabBarView(
            children: [
              _DocEditor(kind: _DocKind.memory),
              _DocEditor(kind: _DocKind.soul),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, WidgetRef ref, String value) async {
    if (value != 'reset') return;
    final ok = await showCareConfirmDialog(
      context,
      title: '恢复默认设置？',
      message: '「我的记忆」和「Care 的性格」都会恢复为初始模板，你之前的修改将被覆盖。',
      confirmLabel: '恢复默认',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(careMemoryProvider.notifier).resetDefaults();
      if (context.mounted) showCareSnack(context, '已恢复默认');
    } catch (_) {
      if (context.mounted) showCareSnack(context, '恢复失败，请稍后再试。');
    }
  }
}

class _DocEditor extends ConsumerStatefulWidget {
  const _DocEditor({required this.kind});

  final _DocKind kind;

  @override
  ConsumerState<_DocEditor> createState() => _DocEditorState();
}

class _DocEditorState extends ConsumerState<_DocEditor>
    with AutomaticKeepAliveClientMixin {
  final _ctrl = TextEditingController();
  bool _editing = false;
  bool _saving = false;
  String _original = '';

  bool get _isMemory => widget.kind == _DocKind.memory;
  bool get _dirty => _editing && _ctrl.text != _original;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _read(CareMemoryState s) => _isMemory ? s.memoryMarkdown : s.soulMarkdown;

  void _startEdit(String current) {
    setState(() {
      _original = current;
      _ctrl.text = current;
      _editing = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ctrl = ref.read(careMemoryProvider.notifier);
    try {
      if (_isMemory) {
        await ctrl.saveMemory(_ctrl.text);
      } else {
        await ctrl.saveSoul(_ctrl.text);
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editing = false;
      });
      showCareSnack(context, '已保存到本机');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showCareSnack(context, '保存失败，请稍后再试。');
    }
  }

  Future<void> _cancel() async {
    if (_dirty) {
      final discard = await showCareConfirmDialog(
        context,
        title: '放弃修改？',
        message: '你还有未保存的修改。',
        confirmLabel: '放弃',
        destructive: true,
      );
      if (!discard) return;
    }
    if (mounted) setState(() => _editing = false);
  }

  Future<void> _copyAll(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showCareSnack(context, '已复制全文，可粘贴到任意地方备份');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final doc = ref.watch(
      careMemoryProvider.select((s) => s.value == null ? '' : _read(s.value!)),
    );
    final lastSavedAt = ref.watch(
      careMemoryProvider.select((s) => s.value?.lastSavedAt),
    );
    final fileName = _isMemory ? 'MEMORY.md' : 'SOUL.md';

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await showCareConfirmDialog(
          context,
          title: '放弃修改？',
          message: '你还有未保存的修改。',
          confirmLabel: '放弃',
          destructive: true,
        );
        if (discard && context.mounted) {
          setState(() => _editing = false);
          Navigator.of(context).pop();
        }
      },
      child: CareContentWidth(
        child: _editing
            ? Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        controller: _ctrl,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        autofocus: true,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        onChanged: (_) => setState(() {}),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.55,
                        ),
                        decoration: InputDecoration(
                          helperText: '支持 Markdown：# 标题、- 列表、**加粗**',
                          helperStyle:
                              TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving ? null : _cancel,
                              child: const Text('取消'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _saving ? null : _save,
                              child: _saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.5),
                                    )
                                  : const Text('保存'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: SelectionArea(
                        child: CareMarkdownView(
                          markdown: doc,
                          baseStyle: theme.textTheme.bodyMedium
                              ?.copyWith(height: 1.6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          lastSavedAt != null
                              ? '仅保存在本机 · $fileName · ${careClockTime(lastSavedAt)} 已保存'
                              : '仅保存在本机 · $fileName',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _copyAll(doc),
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          label: const Text('复制全文'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _startEdit(doc),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('编辑'),
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

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40),
            const SizedBox(height: 12),
            const Text('暂时无法读取本机记忆文件'),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
