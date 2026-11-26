import 'package:care_app/state/care_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../common/care_copy.dart';
import '../common/care_widgets.dart';

/// 设置 → 本地加密备份与迁移 (M4): zero-cloud AES-256-GCM export/import &
/// pure Markdown data sovereignty export.
class CareBackupPage extends ConsumerStatefulWidget {
  const CareBackupPage({super.key});

  @override
  ConsumerState<CareBackupPage> createState() => _CareBackupPageState();
}

class _CareBackupPageState extends ConsumerState<CareBackupPage> {
  final _exportPass = TextEditingController();
  final _importPass = TextEditingController();
  final _importData = TextEditingController();
  bool _obscureExport = true;
  bool _obscureImport = true;

  @override
  void dispose() {
    _exportPass.dispose();
    _importPass.dispose();
    _importData.dispose();
    super.dispose();
  }

  Future<void> _exportEncrypted() async {
    FocusScope.of(context).unfocus();
    try {
      await ref
          .read(careBackupProvider.notifier)
          .exportEncryptedBackup(_exportPass.text);
      _exportPass.clear();
      if (mounted) showCareSnack(context, '加密备份已生成，可点击下方按钮复制保存');
    } on FormatException catch (e) {
      if (mounted) showCareSnack(context, e.message);
    } catch (_) {
      if (mounted) showCareSnack(context, '生成加密备份失败，请稍后再试。');
    }
  }

  Future<void> _importEncrypted() async {
    FocusScope.of(context).unfocus();
    final confirm = await showCareConfirmDialog(
      context,
      title: '确认从备份恢复？',
      message: '将覆盖本机性格设定、长期记忆、定时任务与专职 Bot，API Key 不受影响。',
      confirmLabel: '恢复',
    );
    if (!confirm || !mounted) return;
    try {
      final summary = await ref.read(careBackupProvider.notifier).importEncryptedBackup(
            passphrase: _importPass.text,
            envelopeJson: _importData.text,
          );
      _importPass.clear();
      _importData.clear();
      if (mounted) {
        showCareSnack(
          context,
          '恢复成功：已导入 ${summary.routineCount} 个定时任务与 ${summary.specialistCount} 个 Bot',
        );
      }
    } on FormatException catch (e) {
      if (mounted) showCareSnack(context, e.message);
    } catch (_) {
      if (mounted) showCareSnack(context, '解密失败：请检查备份口令或内容是否完整。');
    }
  }

  Future<void> _copyMarkdown() async {
    try {
      final md = await ref.read(careBackupProvider.notifier).exportPlainMarkdown();
      await Clipboard.setData(ClipboardData(text: md));
      if (mounted) showCareSnack(context, '已复制全部 Markdown 记忆与配置，可粘贴到任意笔记软件');
    } catch (_) {
      if (mounted) showCareSnack(context, '导出失败，请稍后再试。');
    }
  }

  Future<void> _pasteEnvelope() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text?.trim();
    if (text != null && text.isNotEmpty) {
      setState(() => _importData.text = text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backup = ref.watch(careBackupProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('本地加密备份与迁移')),
      body: CareContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            // ── Export Encrypted Card ──
            Text(
              '生成加密备份',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _exportPass,
                      enabled: !backup.isBusy,
                      obscureText: _obscureExport,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: '设置备份口令（至少 6 位）',
                        prefixIcon: const Icon(Icons.password_rounded),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _obscureExport = !_obscureExport),
                          icon: Icon(
                            _obscureExport
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: backup.isBusy ? null : _exportEncrypted,
                        icon: const Icon(Icons.enhanced_encryption_outlined,
                            size: 18),
                        label: Text(backup.isBusy ? '正在加密…' : '生成加密备份'),
                      ),
                    ),
                    if (backup.lastEnvelope != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (backup.lastSummary != null)
                              Text(
                                '生成于 ${careClockTime(backup.lastSummary!.exportedAt)} · '
                                '${backup.lastSummary!.routineCount} 个定时任务 · '
                                '${backup.lastSummary!.specialistCount} 个专职 Bot',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: scheme.primary),
                              ),
                            const SizedBox(height: 6),
                            Text(
                              backup.lastEnvelope!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(fontFamily: 'monospace'),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(64, 38),
                                ),
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: backup.lastEnvelope!),
                                  );
                                  if (context.mounted) {
                                    showCareSnack(context, '加密备份已复制，可保存到你的私人网盘或文件');
                                  }
                                },
                                icon: const Icon(Icons.content_copy_rounded,
                                    size: 16),
                                label: const Text('复制加密备份'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            // ── Import Encrypted Card ──
            Text(
              '从加密备份恢复',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _importData,
                      enabled: !backup.isBusy,
                      minLines: 3,
                      maxLines: 5,
                      autocorrect: false,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      decoration: InputDecoration(
                        labelText: '加密备份内容',
                        hintText: '{"format":"care-backup-v1",...}',
                        suffixIcon: IconButton(
                          tooltip: '粘贴',
                          onPressed: backup.isBusy ? null : _pasteEnvelope,
                          icon: const Icon(Icons.content_paste_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _importPass,
                      enabled: !backup.isBusy,
                      obscureText: _obscureImport,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: '备份口令',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _obscureImport = !_obscureImport),
                          icon: Icon(
                            _obscureImport
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: backup.isBusy ? null : _importEncrypted,
                        icon: const Icon(Icons.restore_rounded, size: 18),
                        label: const Text('解密并恢复'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            // ── Plain Markdown Export ──
            Text(
              '透明可读导出',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            CareHintCard(
              icon: Icons.description_outlined,
              title: '导出纯文本 Markdown',
              body: '导出 SOUL.md、MEMORY.md 与定时任务清单。',
              action: FilledButton.tonalIcon(
                onPressed: _copyMarkdown,
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('复制 Markdown 全文'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
