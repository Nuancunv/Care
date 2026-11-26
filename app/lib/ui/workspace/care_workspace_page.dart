import 'dart:convert';

import 'package:care_app/services/care_workspace_bridge.dart';
import 'package:care_app/state/care_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../care_theme.dart';
import '../chat/care_chat_page.dart';
import '../common/care_copy.dart';
import '../common/care_markdown_view.dart';
import '../common/care_widgets.dart';

bool careIsHtmlPath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.html') || lower.endsWith('.htm');
}

String careWorkspaceFileTypeLabel(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'HTML 网页';
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) return 'Markdown 文档';
  if (lower.endsWith('.pdf')) return 'PDF 文档';
  if (lower.endsWith('.doc') || lower.endsWith('.docx')) return 'Word 文档';
  if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return 'Excel 表格';
  if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) return 'PPT 演示';
  if (lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp')) {
    return '图片';
  }
  if (lower.endsWith('.json')) return 'JSON 数据';
  if (lower.endsWith('.csv')) return 'CSV 表格';
  if (lower.endsWith('.py')) return 'Python 脚本';
  if (lower.endsWith('.js') || lower.endsWith('.ts')) return 'JS / TS 代码';
  if (lower.endsWith('.dart')) return 'Dart 代码';
  if (lower.endsWith('.kt') || lower.endsWith('.java')) return 'Kotlin / Java 代码';
  if (lower.endsWith('.txt')) return '文本文档';
  return '文件';
}

IconData careWorkspaceFileIcon(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.html') || lower.endsWith('.htm')) {
    return Icons.language_rounded;
  }
  if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
  if (lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp')) {
    return Icons.image_outlined;
  }
  if (lower.endsWith('.md') || lower.endsWith('.markdown') || lower.endsWith('.txt')) {
    return Icons.description_outlined;
  }
  if (lower.endsWith('.csv') || lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
    return Icons.table_chart_outlined;
  }
  if (lower.endsWith('.json') ||
      lower.endsWith('.py') ||
      lower.endsWith('.dart') ||
      lower.endsWith('.js') ||
      lower.endsWith('.ts') ||
      lower.endsWith('.kt') ||
      lower.endsWith('.java') ||
      lower.endsWith('.css')) {
    return Icons.code_rounded;
  }
  return Icons.insert_drive_file_outlined;
}

/// Opens a rich format-aware preview sheet for any workspace/library file
/// (HTML WebView render, Markdown, formatted JSON, CSV table, code, + system default app open).
Future<void> showCareWorkspaceFileSheet(
  BuildContext context,
  WidgetRef ref,
  String path, {
  bool preferRenderedHtml = false,
}) async {
  final isPrivate = ref.read(careWorkspaceProvider).value?.isPrivate ?? false;
  if (preferRenderedHtml && careIsHtmlPath(path)) {
    final launched = await ref
        .read(careWorkspaceProvider.notifier)
        .openHtmlPreview(path);
    if (launched) return;
  }

  final content = await ref.read(careWorkspaceProvider.notifier).readFile(path);
  if (!context.mounted) return;
  if (content == null) {
    showCareSnack(context, '无法读取该文件。');
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _CareFilePreviewSheet(
      path: path,
      content: content,
      isPrivate: isPrivate,
      onOpenHtml: () async {
        final ok = await ref
            .read(careWorkspaceProvider.notifier)
            .openHtmlPreview(path);
        if (!ok && ctx.mounted) showCareSnack(ctx, '无法启动网页渲染预览');
      },
      onOpenExternal: () async {
        final ok = await ref
            .read(careWorkspaceProvider.notifier)
            .openWithExternalApp(path);
        if (!ok && ctx.mounted) {
          showCareSnack(ctx, isPrivate ? '隐私 Bot 文件禁止外部应用打开' : '未找到可打开此文件的默认应用');
        }
      },
    ),
  );
}

class _CareFilePreviewSheet extends StatefulWidget {
  const _CareFilePreviewSheet({
    required this.path,
    required this.content,
    required this.isPrivate,
    required this.onOpenHtml,
    required this.onOpenExternal,
  });

  final String path;
  final String content;
  final bool isPrivate;
  final VoidCallback onOpenHtml;
  final VoidCallback onOpenExternal;

  @override
  State<_CareFilePreviewSheet> createState() => _CareFilePreviewSheetState();
}

class _CareFilePreviewSheetState extends State<_CareFilePreviewSheet> {
  bool _showRawSource = false;

  bool get _isHtml => careIsHtmlPath(widget.path);
  bool get _isMarkdown {
    final l = widget.path.toLowerCase();
    return l.endsWith('.md') || l.endsWith('.markdown');
  }

  bool get _isCsv => widget.path.toLowerCase().endsWith('.csv');
  bool get _isJson => widget.path.toLowerCase().endsWith('.json');

  String get _prettyJson {
    try {
      final decoded = jsonDecode(widget.content);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return widget.content;
    }
  }

  List<List<String>> _parseCsv(String raw) {
    final lines = raw
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(80)
        .toList();
    return [for (final line in lines) line.split(',').map((c) => c.trim()).toList()];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasRichToggle = _isMarkdown || _isCsv;

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Icon(careWorkspaceFileIcon(widget.path),
                      size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.path,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: '复制',
                    icon: const Icon(Icons.content_copy_rounded, size: 19),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: widget.content));
                      if (context.mounted) showCareSnack(context, '内容已复制');
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_isHtml)
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(64, 38),
                      ),
                      onPressed: widget.onOpenHtml,
                      icon: const Icon(Icons.language_rounded, size: 18),
                      label: const Text('渲染网页'),
                    ),
                  if (hasRichToggle)
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: false, label: Text('渲染视图')),
                        ButtonSegment(value: true, label: Text('源码')),
                      ],
                      selected: {_showRawSource},
                      onSelectionChanged: (set) {
                        if (set.isNotEmpty) {
                          setState(() => _showRawSource = set.first);
                        }
                      },
                    ),
                  if (!widget.isPrivate)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(64, 38),
                      ),
                      onPressed: widget.onOpenExternal,
                      icon: const Icon(Icons.open_in_new_rounded, size: 17),
                      label: const Text('默认应用打开'),
                    ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(20),
                child: _buildBody(theme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isMarkdown && !_showRawSource) {
      return SelectionArea(child: CareMarkdownView(markdown: widget.content));
    }
    if (_isCsv && !_showRawSource) {
      final rows = _parseCsv(widget.content);
      if (rows.isNotEmpty) {
        final colCount = rows.first.length;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              for (var i = 0; i < colCount; i++)
                DataColumn(label: Text(rows.first[i])),
            ],
            rows: [
              for (final r in rows.skip(1))
                DataRow(
                  cells: [
                    for (var i = 0; i < colCount; i++)
                      DataCell(Text(i < r.length ? r[i] : '')),
                  ],
                ),
            ],
          ),
        );
      }
    }
    return SelectableText(
      _isJson ? _prettyJson : widget.content,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontFamily: 'monospace',
        height: 1.5,
      ),
    );
  }
}

/// Local per-Bot Knowledge Library (`资料库/`) + Agent Workspace explorer.
class CareWorkspacePage extends ConsumerStatefulWidget {
  const CareWorkspacePage({
    super.key,
    this.initialOpenPath,
    this.initialTab = 0,
  });

  final String? initialOpenPath;

  /// `0` = 资料库 (Notebook knowledge base), `1` = 工作区文件.
  final int initialTab;

  @override
  ConsumerState<CareWorkspacePage> createState() => _CareWorkspacePageState();
}

class _CareWorkspacePageState extends ConsumerState<CareWorkspacePage> {
  @override
  void initState() {
    super.initState();
    final initial = widget.initialOpenPath;
    if (initial != null && initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showCareWorkspaceFileSheet(
            context,
            ref,
            initial,
            preferRenderedHtml: true,
          );
        }
      });
    }
  }

  Future<void> _importMaterial() async {
    try {
      final imported =
          await ref.read(careWorkspaceProvider.notifier).importToLibrary();
      if (!mounted) return;
      if (imported != null) {
        showCareSnack(context, '已导入至资料库：$imported');
      }
    } catch (_) {
      if (mounted) showCareSnack(context, '导入资料失败，请稍后再试。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(careWorkspaceProvider);
    final activeBot = ref.watch(
      careBotsProvider.select((s) => s.value?.activeBot ?? kChiefBotProfile),
    );

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab.clamp(0, 1),
      child: CareAtmosphereBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text('${activeBot.name} · 资料库与工作空间'),
            actions: [
              IconButton(
                tooltip: '导入资料',
                icon: const Icon(Icons.upload_file_outlined),
                onPressed: _importMaterial,
              ),
              IconButton(
                tooltip: '新建文件',
                icon: const Icon(Icons.note_add_outlined),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const _NewWorkspaceFileDialog(),
                ),
              ),
              IconButton(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () =>
                    ref.read(careWorkspaceProvider.notifier).refresh(),
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: '资料库'),
                Tab(text: '工作区文件'),
              ],
            ),
          ),
          body: ws.when(
            skipLoadingOnReload: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: FilledButton(
                onPressed: () => ref.invalidate(careWorkspaceProvider),
                child: const Text('重试'),
              ),
            ),
            data: (s) => CareContentWidth(
              child: TabBarView(
                children: [
                  _FileListTab(
                    isLibrary: true,
                    isPrivate: s.isPrivate,
                    files: s.libraryFiles,
                    onImport: _importMaterial,
                    onNewNote: () => showDialog<void>(
                      context: context,
                      builder: (_) => const _NewWorkspaceFileDialog(
                        inLibrary: true,
                      ),
                    ),
                  ),
                  _FileListTab(
                    isLibrary: false,
                    isPrivate: s.isPrivate,
                    files: s.outputFiles,
                    onImport: _importMaterial,
                    onNewNote: () => showDialog<void>(
                      context: context,
                      builder: (_) => const _NewWorkspaceFileDialog(
                        inLibrary: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileListTab extends ConsumerWidget {
  const _FileListTab({
    required this.isLibrary,
    required this.isPrivate,
    required this.files,
    required this.onImport,
    required this.onNewNote,
  });

  final bool isLibrary;
  final bool isPrivate;
  final List<CareWorkspaceFile> files;
  final VoidCallback onImport;
  final VoidCallback onNewNote;

  Future<void> _runStudio(BuildContext context, WidgetRef ref, String mode) async {
    final (String filename, String prompt) = switch (mode) {
      'flashcards' => (
          'studio_flashcards.html',
          '请先使用 `knowledge_list` 和 `workspace_read` 阅读我「资料库」中的全部资料，提炼核心知识点，然后用 `workspace_write` 在工作空间创建一个移动端适配、可点击 3D 翻页、带进度条和「已掌握/再复习」标记的离线交互式 HTML 复习闪卡网页 `studio_flashcards.html`。完成后简要告诉我共整理了多少张闪卡。',
        ),
      'quiz' => (
          'studio_quiz.html',
          '请先使用 `knowledge_list` 和 `workspace_read` 阅读我「资料库」中的全部资料，设计 6~10 道高质量选择题/判断题，然后用 `workspace_write` 在工作空间创建一个移动端适配、支持逐题作答、即时解析与最终评分的离线交互式 HTML 自测网页 `studio_quiz.html`。完成后简要介绍题目覆盖的重点。',
        ),
      _ => (
          'studio_mindmap.html',
          '请先使用 `knowledge_list` 和 `workspace_read` 阅读我「资料库」中的全部资料，梳理出清晰的知识树结构，然后用 `workspace_write` 在工作空间创建一个移动端适配、支持节点展开折叠与高亮搜索的离线交互式 HTML 思维导图/一页总览网页 `studio_mindmap.html`。完成后简要总结核心脉络。',
        ),
    };
    ref.read(careChatProvider.notifier).sendMessage(prompt);
    showCareSnack(context, '正在生成 $filename，已返回对话查看进度');
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const CareChatPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        if (isLibrary) ...[
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, 42),
                  ),
                  onPressed: onImport,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('导入资料文件'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(64, 42),
                  ),
                  onPressed: onNewNote,
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('新建资料笔记'),
                ),
              ),
            ],
          ),
          if (files.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ActionChip(
                    avatar: Icon(Icons.style_outlined,
                        size: 16, color: scheme.primary),
                    label: const Text('生成翻页闪卡'),
                    shape: const StadiumBorder(),
                    onPressed: () => _runStudio(context, ref, 'flashcards'),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: Icon(Icons.quiz_outlined,
                        size: 16, color: scheme.primary),
                    label: const Text('生成交互测验'),
                    shape: const StadiumBorder(),
                    onPressed: () => _runStudio(context, ref, 'quiz'),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: Icon(Icons.account_tree_outlined,
                        size: 16, color: scheme.primary),
                    label: const Text('生成一页导图'),
                    shape: const StadiumBorder(),
                    onPressed: () => _runStudio(context, ref, 'mindmap'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
        if (files.isEmpty)
          CareHintCard(
            icon: isLibrary
                ? Icons.menu_book_outlined
                : Icons.folder_open_outlined,
            title: isLibrary ? '资料库为空' : '工作区为空',
            body: isLibrary
                ? '导入课件、文档或新建笔记到「资料库」，对话时 Bot 会检索资料内容并据实回答。'
                : '让 Bot 编写网页、脚本或文档时，文件会保存在这里。',
          )
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < files.length; i++) ...[
                  if (i > 0) const Divider(indent: 18, endIndent: 18),
                  ListTile(
                    key: ValueKey(files[i].path),
                    leading: Icon(
                      careWorkspaceFileIcon(files[i].path),
                      color: scheme.primary,
                    ),
                    title: Text(
                      files[i].displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${careWorkspaceFileTypeLabel(files[i].path)} · ${_formatBytes(files[i].sizeBytes)} · ${careRelativeTime(files[i].modifiedAt)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (careIsHtmlPath(files[i].path))
                          IconButton(
                            tooltip: '渲染网页',
                            icon: Icon(Icons.language_rounded,
                                size: 20, color: scheme.primary),
                            onPressed: () => ref
                                .read(careWorkspaceProvider.notifier)
                                .openHtmlPreview(files[i].path),
                          ),
                        if (!isPrivate)
                          IconButton(
                            tooltip: '默认应用打开',
                            icon: Icon(Icons.open_in_new_rounded,
                                size: 19, color: scheme.onSurfaceVariant),
                            onPressed: () async {
                              final ok = await ref
                                  .read(careWorkspaceProvider.notifier)
                                  .openWithExternalApp(files[i].path);
                              if (!ok && context.mounted) {
                                showCareSnack(context, '未找到可打开此文件的默认应用');
                              }
                            },
                          ),
                        IconButton(
                          tooltip: '删除',
                          icon: Icon(Icons.delete_outline_rounded,
                              size: 19, color: scheme.onSurfaceVariant),
                          onPressed: () async {
                            final ok = await showCareConfirmDialog(
                              context,
                              title: '删除「${files[i].displayName}」？',
                              message: '删除后无法恢复。',
                              confirmLabel: '删除',
                              destructive: true,
                            );
                            if (ok) {
                              await ref
                                  .read(careWorkspaceProvider.notifier)
                                  .deleteFile(files[i].path);
                            }
                          },
                        ),
                      ],
                    ),
                    onTap: () => showCareWorkspaceFileSheet(
                      context,
                      ref,
                      files[i].path,
                      preferRenderedHtml: careIsHtmlPath(files[i].path),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _NewWorkspaceFileDialog extends ConsumerStatefulWidget {
  const _NewWorkspaceFileDialog({this.inLibrary = false});

  final bool inLibrary;

  @override
  ConsumerState<_NewWorkspaceFileDialog> createState() =>
      _NewWorkspaceFileDialogState();
}

class _NewWorkspaceFileDialogState
    extends ConsumerState<_NewWorkspaceFileDialog> {
  final _path = TextEditingController();
  final _content = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _path.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _path.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = '请输入文件名，例如 notes.md');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ctrl = ref.read(careWorkspaceProvider.notifier);
      if (widget.inLibrary) {
        await ctrl.addLibraryNote(raw, _content.text);
      } else {
        await ctrl.writeFile(raw, _content.text);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '保存失败，请检查文件名格式';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.inLibrary ? '新建资料笔记' : '新建文件'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _path,
              autofocus: true,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: '文件名',
                hintText: widget.inLibrary ? '第一章笔记.md' : 'index.html / plan.md',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _content,
              enabled: !_busy,
              minLines: 4,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(labelText: '内容'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: _busy ? null : _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
