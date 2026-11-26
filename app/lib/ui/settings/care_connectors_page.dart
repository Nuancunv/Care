import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../common/care_widgets.dart';

/// 设置 → 连接邮箱与扩展: personal IMAP/SMTP mailbox and MCP extensions (M2).
///
/// The mailbox authorization code is written straight into Android Keystore by
/// the state layer; the UI only ever sees `hasPassword`.
class CareConnectorsPage extends ConsumerWidget {
  const CareConnectorsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectors = ref.watch(careConnectorProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('邮箱与扩展')),
      body: connectors.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: FilledButton(
            onPressed: () => ref.invalidate(careConnectorProvider),
            child: const Text('重试'),
          ),
        ),
        data: (s) => CareContentWidth(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const CareSectionHeader('个人邮箱'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _MailCard(account: s.mailAccount),
              ),
              const CareSectionHeader('扩展服务（MCP）'),
              if (s.mcpServers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: CareHintCard(
                    icon: Icons.extension_outlined,
                    title: '还没有扩展服务',
                    body: '添加你的 HTTPS MCP 服务地址。',
                    action: FilledButton.tonalIcon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const _McpDialog(),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('添加扩展服务'),
                    ),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < s.mcpServers.length; i++) ...[
                          if (i > 0) const Divider(indent: 20, endIndent: 20),
                          _McpServerTile(server: s.mcpServers[i]),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: OutlinedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const _McpDialog(),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('添加扩展服务'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _McpServerTile extends ConsumerWidget {
  const _McpServerTile({required this.server});

  final CareMcpServerConfig server;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: ValueKey(server.id),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      leading: Icon(
        Icons.extension_outlined,
        color: server.enabled ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(server.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        server.endpointUrl,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: server.enabled,
            onChanged: (v) => ref
                .read(careConnectorProvider.notifier)
                .toggleMcpServer(server.id, v),
          ),
          IconButton(
            tooltip: '移除 ${server.name}',
            icon: Icon(Icons.delete_outline_rounded,
                size: 20, color: scheme.onSurfaceVariant),
            onPressed: () async {
              final ok = await showCareConfirmDialog(
                context,
                title: '移除「${server.name}」？',
                message: 'Care 将不再使用这个扩展服务。',
                confirmLabel: '移除',
                destructive: true,
              );
              if (ok) {
                await ref
                    .read(careConnectorProvider.notifier)
                    .removeMcpServer(server.id);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _MailCard extends ConsumerWidget {
  const _MailCard({required this.account});

  final CareMailAccountConfig? account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final a = account;
    if (a == null) {
      return CareHintCard(
        icon: Icons.mail_outline_rounded,
        title: '连接你的邮箱',
        body: '连接后，Care 可以帮你整理邮件、起草回复。任何发送操作都会先请你确认。',
        action: FilledButton.tonal(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CareMailFormPage()),
          ),
          child: const Text('添加邮箱'),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.mail_rounded),
            title: Text(a.email),
            subtitle: Text(
              a.hasPassword ? '已连接 · 授权码安全保存在本机' : '缺少授权码，暂时无法收发邮件',
              style: TextStyle(color: a.hasPassword ? null : scheme.error),
            ),
          ),
          ListTile(
            dense: true,
            title: const Text('收信服务器'),
            trailing: Text('${a.imapHost}:${a.imapPort}'),
          ),
          ListTile(
            dense: true,
            title: const Text('发信服务器'),
            trailing: Text('${a.smtpHost}:${a.smtpPort}'),
          ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () async {
                  final ok = await showCareConfirmDialog(
                    context,
                    title: '移除邮箱？',
                    message: '邮箱设置和本机保存的授权码都会被删除。',
                    confirmLabel: '移除',
                    destructive: true,
                  );
                  if (ok) {
                    await ref.read(careConnectorProvider.notifier).removeMailAccount();
                  }
                },
                child: Text('移除', style: TextStyle(color: scheme.error)),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CareMailFormPage(existing: a),
                  ),
                ),
                child: const Text('编辑'),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mailbox form with common-provider presets.
class CareMailFormPage extends ConsumerStatefulWidget {
  const CareMailFormPage({super.key, this.existing});

  final CareMailAccountConfig? existing;

  @override
  ConsumerState<CareMailFormPage> createState() => _CareMailFormPageState();
}

class _CareMailFormPageState extends ConsumerState<CareMailFormPage> {
  static const _presets = <String, (String, String)>{
    'qq.com': ('imap.qq.com', 'smtp.qq.com'),
    'foxmail.com': ('imap.qq.com', 'smtp.qq.com'),
    '163.com': ('imap.163.com', 'smtp.163.com'),
    '126.com': ('imap.126.com', 'smtp.126.com'),
    'gmail.com': ('imap.gmail.com', 'smtp.gmail.com'),
    'outlook.com': ('outlook.office365.com', 'smtp.office365.com'),
    'hotmail.com': ('outlook.office365.com', 'smtp.office365.com'),
    'icloud.com': ('imap.mail.me.com', 'smtp.mail.me.com'),
  };

  late final _email = TextEditingController(text: widget.existing?.email);
  late final _imap = TextEditingController(text: widget.existing?.imapHost);
  late final _imapPort =
      TextEditingController(text: '${widget.existing?.imapPort ?? 993}');
  late final _smtp = TextEditingController(text: widget.existing?.smtpHost);
  late final _smtpPort =
      TextEditingController(text: '${widget.existing?.smtpPort ?? 465}');
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_email, _imap, _imapPort, _smtp, _smtpPort, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyPreset(String email) {
    final at = email.lastIndexOf('@');
    if (at < 0) return;
    final preset = _presets[email.substring(at + 1).toLowerCase()];
    if (preset == null) return;
    if (_imap.text.isEmpty) _imap.text = preset.$1;
    if (_smtp.text.isEmpty) _smtp.text = preset.$2;
  }

  Future<void> _save() async {
    final hasStored = widget.existing?.hasPassword ?? false;
    if (_password.text.trim().isEmpty && !hasStored) {
      setState(() => _error = '请填写邮箱授权码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(careConnectorProvider.notifier).saveMailAccount(
            email: _email.text,
            imapHost: _imap.text,
            imapPort: int.tryParse(_imapPort.text.trim()) ?? 993,
            smtpHost: _smtp.text,
            smtpPort: int.tryParse(_smtpPort.text.trim()) ?? 465,
            appPassword: _password.text.trim().isEmpty ? null : _password.text,
          );
      _password.clear();
      if (mounted) {
        Navigator.of(context).pop();
        showCareSnack(context, '邮箱已保存');
      }
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message.contains('email')
              ? '邮箱地址格式不正确'
              : '请填写收信和发信服务器地址';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '保存失败，请稍后再试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasStored = widget.existing?.hasPassword ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? '添加邮箱' : '编辑邮箱')),
      body: CareContentWidth(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              onChanged: _applyPreset,
              decoration: const InputDecoration(labelText: '邮箱地址'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '授权码',
                helperText: hasStored
                    ? '已保存在本机安全区域，留空则保持不变'
                    : '在邮箱网页版的设置中开启 IMAP/SMTP 后生成，不是登录密码',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('服务器', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '常见邮箱会自动填写，一般无需修改。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _imap,
                    enabled: !_busy,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: '收信 (IMAP)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _imapPort,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '端口'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _smtp,
                    enabled: !_busy,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: '发信 (SMTP)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _smtpPort,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '端口'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

class _McpDialog extends ConsumerStatefulWidget {
  const _McpDialog();

  @override
  ConsumerState<_McpDialog> createState() => _McpDialogState();
}

class _McpDialogState extends ConsumerState<_McpDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '请给它起个名字');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(careConnectorProvider.notifier).addMcpServer(
            name: _name.text,
            endpointUrl: _url.text,
          );
      if (mounted) Navigator.of(context).pop();
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message.contains('HTTPS')
              ? '远程地址需要以 https:// 开头（本机地址除外）'
              : '地址格式不正确';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '添加失败，请稍后再试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加扩展服务'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: '名称', hintText: '例如：我的 Notion'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            enabled: !_busy,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: '服务地址',
              hintText: 'https://',
              errorText: _error,
              errorMaxLines: 2,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: _busy ? null : _save,
          child: const Text('添加'),
        ),
      ],
    );
  }
}
