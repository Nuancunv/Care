import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../automation/care_automation_page.dart';
import '../care_theme.dart';
import '../chat/care_model_sheet.dart';
import '../common/care_copy.dart';
import '../common/care_widgets.dart';
import '../workspace/care_workspace_page.dart';
import 'care_backup_page.dart';
import 'care_diagnostics_page.dart';
import 'care_proactive_page.dart';

const _kDefaultBaseUrl = 'https://api.deepseek.com/v1';

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: builder)),
    );
  }
}

class CareSettingsPage extends ConsumerWidget {
  const CareSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(careSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: settings.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('暂时无法读取设置'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(careSettingsProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (s) => CareContentWidth(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const CareSectionHeader('模型与密钥'),
              ListTile(
                leading: const Icon(Icons.key_rounded),
                title: const Text('DeepSeek API Key'),
                subtitle: Text(s.maskedApiKey ?? '未设置'),
                trailing: TextButton(
                  onPressed: () => _changeKey(context, ref),
                  child: Text(s.hasApiKey ? '更换' : '填写'),
                ),
              ),
              _ConnectionTile(state: s),
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('主 Bot 模型与思考'),
                subtitle: Text(
                  '${careModelLabel(s.activeModel)} · ${careEffortLabel(s.activeEffort)}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showCareModelEffortSheet(
                  context,
                  bot: ref.read(careBotsProvider).value?.chiefBot ??
                      kChiefBotProfile,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.link_rounded),
                title: const Text('服务地址'),
                subtitle: Text(
                  s.baseUrl == _kDefaultBaseUrl ? 'DeepSeek 官方（默认）' : s.baseUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _editBaseUrl(context, ref, s.baseUrl),
              ),
              const CareSectionHeader('本次用量'),
              const _UsageCard(),
              const CareSectionHeader('主动关怀与扩展'),
              _NavTile(
                icon: Icons.wb_twilight_rounded,
                title: '主动关怀',
                subtitle: '早晚简报、免打扰与日历通知',
                builder: (_) => const CareProactivePage(),
              ),
              _NavTile(
                icon: Icons.touch_app_outlined,
                title: '手机自动化',
                subtitle: '跨应用操作、定时任务与紧急停止',
                builder: (_) => const CareAutomationPage(),
              ),
              _NavTile(
                icon: Icons.folder_outlined,
                title: '资料库与工作空间',
                subtitle: '查看 Bot 资料库、代码与文档',
                builder: (_) => const CareWorkspacePage(),
              ),
              const CareSectionHeader('外观'),
              const _AppearanceCard(),
              const CareSectionHeader('后台与耗电'),
              const _BatteryTile(),
              const CareSectionHeader('隐私'),
              _NavTile(
                icon: Icons.enhanced_encryption_outlined,
                title: '本地加密备份与迁移',
                subtitle: 'AES-256 加密导出、恢复与 Markdown 导出',
                builder: (_) => const CareBackupPage(),
              ),
              const ListTile(
                leading: Icon(Icons.fingerprint_rounded),
                title: Text('Privacy Bot 隐藏入口'),
                subtitle: Text('在首页列表底部继续上拉，或在搜索栏输入 privacy 解锁'),
              ),
              if (s.hasApiKey)
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded,
                      color: Theme.of(context).colorScheme.error),
                  title: Text(
                    '移除 API Key',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  subtitle: const Text('从本机安全存储中删除'),
                  onTap: () => _removeKey(context, ref),
                ),
              const CareSectionHeader('更多'),
              ListTile(
                leading: const Icon(Icons.monitor_heart_outlined),
                title: const Text('高级诊断'),
                subtitle: const Text('运行状态、版本信息与日志'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CareDiagnosticsPage(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('关于 Care'),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'Care',
                  applicationVersion: '0.1.0-beta',
                  applicationIcon: const CareAvatar(size: 48),
                  applicationLegalese:
                      '以 AGPL-3.0 协议开源。\n基于 dsh-Go（AGPL-3.0）与 DS-Bot（Apache-2.0）改造，'
                      '感谢上游作者。',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeKey(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _ApiKeyDialog(),
    );
    if (saved != true || !context.mounted) return;
    final ok = await ref.read(careSettingsProvider.notifier).verifyDirectConnection();
    if (!context.mounted) return;
    showCareSnack(
      context,
      ok
          ? '已保存，连接正常'
          : '已保存，但连接测试未通过：${careFriendlyError(ref.read(careSettingsProvider).value?.lastError)}',
    );
  }

  Future<void> _removeKey(BuildContext context, WidgetRef ref) async {
    final ok = await showCareConfirmDialog(
      context,
      title: '移除 API Key？',
      message: '移除后 Care 将无法回复，直到你重新填写。',
      confirmLabel: '移除',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await ref.read(careSettingsProvider.notifier).clearApiKey();
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _editBaseUrl(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _BaseUrlDialog(initial: current),
    );
    if (changed == true && context.mounted) {
      showCareSnack(context, '服务地址已更新，建议重新测试连接');
    }
  }
}

class _ConnectionTile extends ConsumerWidget {
  const _ConnectionTile({required this.state});

  final CareSettingsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color, String text) = state.isVerifying
        ? (Icons.sync_rounded, scheme.primary, '正在测试…')
        : state.connectionVerified
            ? (Icons.check_circle_rounded, scheme.primary, '连接正常')
            : state.lastError != null
                ? (Icons.error_outline_rounded, scheme.error,
                    careFriendlyError(state.lastError))
                : (Icons.help_outline_rounded, scheme.onSurfaceVariant, '尚未测试');

    return ListTile(
      leading: Icon(icon, color: color),
      title: const Text('连接状态'),
      subtitle: Text(text),
      trailing: TextButton(
        onPressed: state.isVerifying || !state.hasApiKey
            ? null
            : () => ref.read(careSettingsProvider.notifier).verifyDirectConnection(),
        child: const Text('测试'),
      ),
    );
  }
}

class _UsageCard extends ConsumerWidget {
  const _UsageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(careChatProvider.select((s) => s.usage));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget cell(String label, int value) => Expanded(
          child: Column(
            children: [
              Text(
                careFormatCount(value),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
          child: Column(
            children: [
              Row(
                children: [
                  cell('总计 tokens', usage.totalTokens),
                  cell('输入', usage.promptTokens),
                  cell('输出', usage.completionTokens),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '本次会话用量，实际以服务商账单为准',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(careThemeModeProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto_outlined, size: 18),
            label: Text('跟随系统'),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_outlined, size: 18),
            label: Text('浅色'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined, size: 18),
            label: Text('深色'),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (set) {
          if (set.isNotEmpty) {
            ref.read(careThemeModeProvider.notifier).setMode(set.first);
          }
        },
      ),
    );
  }
}

class _BatteryTile extends ConsumerStatefulWidget {
  const _BatteryTile();

  @override
  ConsumerState<_BatteryTile> createState() => _BatteryTileState();
}

class _BatteryTileState extends ConsumerState<_BatteryTile>
    with WidgetsBindingObserver {
  bool? _exempt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    try {
      final v = await ref.read(careRuntimeProvider.notifier).isBatteryExempt();
      if (mounted) setState(() => _exempt = v);
    } catch (_) {
      if (mounted) setState(() => _exempt = null);
    }
  }

  Future<void> _request() async {
    try {
      await ref.read(careRuntimeProvider.notifier).requestBatteryExempt();
    } catch (_) {
      if (mounted) showCareSnack(context, '无法打开系统设置，请手动在电池设置中允许 Care 后台运行。');
    }
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final exempt = _exempt == true;
    return ListTile(
      leading: Icon(
        exempt ? Icons.battery_charging_full_rounded : Icons.battery_alert_outlined,
        color: exempt ? scheme.primary : null,
      ),
      title: const Text('允许后台运行'),
      subtitle: Text(
        exempt ? '已允许' : '设为「不受限制」以保证提醒准时',
      ),
      trailing: exempt
          ? Icon(Icons.check_rounded, color: scheme.primary)
          : TextButton(onPressed: _request, child: const Text('去设置')),
    );
  }
}

class _ApiKeyDialog extends ConsumerStatefulWidget {
  const _ApiKeyDialog();

  @override
  ConsumerState<_ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends ConsumerState<_ApiKeyDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = '请粘贴你的 API Key');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(careSettingsProvider.notifier).saveApiKey(raw);
      _ctrl.clear();
      if (mounted) Navigator.of(context).pop(true);
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = careFriendlyError(e.message);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = careFriendlyError(e.toString());
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('更换 API Key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('新的 Key 会加密保存在本机安全区域，并替换原来的 Key。'),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_busy,
            keyboardType: TextInputType.visiblePassword,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              hintText: 'sk-…',
              errorText: _error,
              suffixIcon: IconButton(
                tooltip: _obscure ? '显示' : '隐藏',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
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

class _BaseUrlDialog extends ConsumerStatefulWidget {
  const _BaseUrlDialog({required this.initial});

  final String initial;

  @override
  ConsumerState<_BaseUrlDialog> createState() => _BaseUrlDialogState();
}

class _BaseUrlDialogState extends ConsumerState<_BaseUrlDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save(String url) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(careSettingsProvider.notifier).setBaseUrl(url);
      if (mounted) Navigator.of(context).pop(true);
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = careFriendlyError(e.message);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = careFriendlyError(e.toString());
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('服务地址'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('默认直接连接 DeepSeek 官方。如果你使用其他兼容服务，可以在这里修改。'),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            enabled: !_busy,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(errorText: _error, errorMaxLines: 3),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => _save(_kDefaultBaseUrl),
          child: const Text('恢复默认'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: _busy ? null : () => _save(_ctrl.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
