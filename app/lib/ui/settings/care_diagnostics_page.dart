import 'package:care_app/state/care_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../common/care_copy.dart';
import '../common/care_widgets.dart';

/// 设置 → 高级诊断 (Route A Native Health Dashboard).
///
/// Replaces legacy unbundled PRoot/DSH placeholders with genuinely useful
/// native diagnostics: live API latency test, Bot & Library storage metrics,
/// Android permission health, and redacted diagnostic summary export.
class CareDiagnosticsPage extends ConsumerStatefulWidget {
  const CareDiagnosticsPage({super.key});

  @override
  ConsumerState<CareDiagnosticsPage> createState() =>
      _CareDiagnosticsPageState();
}

class _CareDiagnosticsPageState extends ConsumerState<CareDiagnosticsPage> {
  bool _testingLatency = false;
  int? _latencyMs;
  bool? _latencyOk;
  bool? _batteryExempt;

  @override
  void initState() {
    super.initState();
    _loadBattery();
  }

  Future<void> _loadBattery() async {
    try {
      final exempt =
          await ref.read(careRuntimeProvider.notifier).isBatteryExempt();
      if (mounted) setState(() => _batteryExempt = exempt);
    } catch (_) {}
  }

  Future<void> _testApiLatency() async {
    setState(() => _testingLatency = true);
    final sw = Stopwatch()..start();
    try {
      final ok = await ref
          .read(careSettingsProvider.notifier)
          .verifyDirectConnection();
      sw.stop();
      if (mounted) {
        setState(() {
          _latencyMs = sw.elapsedMilliseconds;
          _latencyOk = ok;
        });
      }
    } finally {
      if (mounted) setState(() => _testingLatency = false);
    }
  }

  Future<void> _copyReport() async {
    final settings = ref.read(careSettingsProvider).value;
    final bots = ref.read(careBotsProvider).value;
    final ws = ref.read(careWorkspaceProvider).value;
    final eco = ref.read(careEcosystemProvider).value;
    final auto = ref.read(careAutomationProvider);
    final report = [
      'Care Native Diagnostics (0.1.0-beta)',
      'Engine: Native Kotlin + Flutter Direct BYOK HTTPS (Zero Cloud Relay)',
      'Endpoint: ${settings?.baseUrl ?? '-'}',
      'Model: ${settings?.activeModel ?? '-'} (${settings?.activeEffort ?? '-'})',
      'Latency: ${_latencyMs != null ? '${_latencyMs}ms (ok=$_latencyOk)' : 'untested'}',
      'Bots: ${(bots?.specialists.length ?? 0) + 1} public + 1 Privacy Bot',
      'Active Library Files: ${ws?.libraryFiles.length ?? 0}',
      'Active Workspace Files: ${ws?.outputFiles.length ?? 0}',
      'Calendar Permission: ${eco?.calendarReadGranted ?? false}',
      'Notice Access: ${eco?.noticeAccessEnabled ?? false}',
      'Accessibility Ready: ${auto.selfCheck.ready}',
      'Battery Exempt: ${_batteryExempt ?? false}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: report));
    if (mounted) showCareSnack(context, '诊断摘要已复制（不含任何密钥或隐私内容）');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(careSettingsProvider).value;
    final bots = ref.watch(careBotsProvider).value;
    final ws = ref.watch(careWorkspaceProvider).value;
    final eco = ref.watch(careEcosystemProvider).value;
    final auto = ref.watch(careAutomationProvider);
    final rt = ref.watch(careRuntimeProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('高级诊断'),
        actions: [
          IconButton(
            tooltip: '复制诊断摘要',
            icon: const Icon(Icons.content_copy_rounded),
            onPressed: _copyReport,
          ),
        ],
      ),
      body: CareContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // ── Native Architecture & Live Latency Card ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bolt_rounded, color: scheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Care 原生直连引擎',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(64, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          onPressed: _testingLatency ? null : _testApiLatency,
                          child: _testingLatency
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('测速'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '纯原生 Kotlin + Flutter 架构 · 零云端中转 · 直连 BYOK HTTPS',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (_latencyMs != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            _latencyOk == true
                                ? Icons.check_circle_rounded
                                : Icons.error_outline_rounded,
                            size: 16,
                            color: _latencyOk == true
                                ? scheme.primary
                                : scheme.error,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _latencyOk == true
                                ? '接口响应正常 · $_latencyMs ms'
                                : '连接异常（$_latencyMs ms）',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _latencyOk == true
                                  ? scheme.primary
                                  : scheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),
            // ── Core Metrics ──
            Card(
              child: Column(
                children: [
                  _InfoRow('服务地址', settings?.baseUrl),
                  _InfoRow(
                    '主 Bot 模型',
                    settings != null
                        ? '${careModelShortLabel(settings.activeModel)} · ${careEffortShortLabel(settings.activeEffort)}'
                        : null,
                  ),
                  _InfoRow(
                    '已创建 Bot',
                    bots != null
                        ? '${bots.specialists.length + 1} 个常用 + 1 个 Privacy Bot'
                        : null,
                  ),
                  _InfoRow(
                    '当前资料库 / 工作区',
                    ws != null
                        ? '${ws.libraryFiles.length} 份资料 · ${ws.outputFiles.length} 个文件'
                        : null,
                  ),
                  _InfoRow('设备架构', rt.abi),
                  const _InfoRow('密钥与隐私隔离', 'Android Keystore + 独立目录'),
                ],
              ),
            ),

            const SizedBox(height: 14),
            // ── Android Capabilities & Permissions ──
            Card(
              child: Column(
                children: [
                  _StatusRow('后台运行白名单', _batteryExempt == true),
                  _StatusRow('系统日历读取', eco?.calendarReadGranted == true),
                  _StatusRow('通知摘要监听', eco?.noticeAccessEnabled == true),
                  _StatusRow('无障碍自动化', auto.selfCheck.ready),
                ],
              ),
            ),

            if (rt.recentLogs.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('本机日志（已脱敏）', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: rt.recentLogs.length,
                  itemBuilder: (_, i) => Text(
                    rt.recentLogs[rt.recentLogs.length - 1 - i],
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 210),
        child: Text(
          (value == null || value!.isEmpty) ? '—' : value!,
          textAlign: TextAlign.end,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow(this.label, this.enabled);

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            enabled
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 16,
            color: enabled ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            enabled ? '已就绪' : '未开启',
            style: TextStyle(
              fontSize: 12,
              color: enabled ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
