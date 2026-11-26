import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../common/care_copy.dart';
import '../common/care_widgets.dart';

/// 设置 → 手机自动化与例程 (M3): accessibility self-check, emergency stop /
/// takeover, and local Routine skills.
///
/// Every high-risk step is still decided by the native SafetyGate approval sheet;
/// this page offers no way to skip it.
class CareAutomationPage extends ConsumerStatefulWidget {
  const CareAutomationPage({super.key});

  @override
  ConsumerState<CareAutomationPage> createState() => _CareAutomationPageState();
}

class _CareAutomationPageState extends ConsumerState<CareAutomationPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from system accessibility settings → re-run the self check.
    if (state == AppLifecycleState.resumed) {
      ref.read(careAutomationProvider.notifier).refreshSelfCheck();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('手机自动化'),
        actions: [
          IconButton(
            tooltip: '重新检测',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                ref.read(careAutomationProvider.notifier).refreshSelfCheck(),
          ),
        ],
      ),
      body: const CareContentWidth(
        child: _AutomationBody(),
      ),
    );
  }
}

class _AutomationBody extends ConsumerWidget {
  const _AutomationBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auto = ref.watch(careAutomationProvider);
    final check = auto.selfCheck;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final outcome = careFriendlyAutomation(auto.lastError) ??
        careFriendlyAutomation(auto.lastOutcome);

    final vendor = '${check.brand} ${check.manufacturer}'.toLowerCase();
    final isColorOs = vendor.contains('oppo') ||
        vendor.contains('oneplus') ||
        vendor.contains('realme');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
      children: [
        if (check.emergencyStopped)
          CareHintCard(
            icon: Icons.pan_tool_rounded,
            tone: scheme.error,
            title: '紧急停止已开启',
            body: '所有自动操作都已暂停，手机完全由你掌控。确认安全后可以恢复。',
            action: FilledButton.tonal(
              onPressed: () async {
                try {
                  await ref
                      .read(careAutomationProvider.notifier)
                      .clearEmergencyStop();
                } catch (_) {
                  if (context.mounted) showCareSnack(context, '恢复失败，请稍后再试。');
                }
              },
              child: const Text('恢复自动化'),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                _CheckTile(
                  ok: check.accessibilityEnabled,
                  title: '无障碍服务',
                  okText: '已开启',
                  badText: '未开启（必需）',
                  action: check.accessibilityEnabled
                      ? null
                      : TextButton(
                          onPressed: () async {
                            try {
                              await ref
                                  .read(careAutomationProvider.notifier)
                                  .openAccessibilitySettings();
                            } catch (_) {
                              if (context.mounted) {
                                showCareSnack(context, '无法打开系统设置。');
                              }
                            }
                          },
                          child: const Text('去开启'),
                        ),
                ),
                _CheckTile(
                  ok: check.accessibilityConnected,
                  title: '服务连接',
                  okText: '运行正常',
                  badText: check.accessibilityEnabled
                      ? '未连接，可尝试重新开启无障碍'
                      : '等待开启无障碍',
                ),
                _CheckTile(
                  ok: check.shizukuInstalled,
                  optional: true,
                  title: 'Shizuku 增强通道',
                  okText: '已安装',
                  badText: '未安装（可选，不影响使用）',
                ),
                if (check.manufacturer.isNotEmpty)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.smartphone_rounded),
                    title: const Text('设备'),
                    trailing: Text(
                      [check.brand, check.manufacturer]
                          .where((e) => e.isNotEmpty)
                          .toSet()
                          .join(' / '),
                    ),
                  ),
                if (!check.accessibilityEnabled && isColorOs)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb_outline_rounded,
                              size: 18, color: scheme.onSecondaryContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'ColorOS 提示：前往「系统设置 → 辅助功能 → 已下载的应用 → Care」开启无障碍即可。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSecondaryContainer,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (check.ready) ...[
          const SizedBox(height: 12),
          _ScreenInspectCard(lastScreen: auto.lastScreen),
        ],
        if (outcome != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  outcome,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
        if (!check.emergencyStopped) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: 0.6)),
            ),
            onPressed: () async {
              try {
                await ref.read(careAutomationProvider.notifier).emergencyStop();
              } catch (_) {
                if (context.mounted) showCareSnack(context, '操作失败，请稍后再试。');
              }
            },
            icon: const Icon(Icons.pan_tool_outlined),
            label: const Text('紧急停止所有自动操作'),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                '定时任务',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const _RoutineDialog(),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('新建'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const _RoutineList(),
      ],
    );
  }
}

class _ScreenInspectCard extends ConsumerStatefulWidget {
  const _ScreenInspectCard({required this.lastScreen});

  final CareScreenSummary? lastScreen;

  @override
  ConsumerState<_ScreenInspectCard> createState() => _ScreenInspectCardState();
}

class _ScreenInspectCardState extends ConsumerState<_ScreenInspectCard> {
  bool _busy = false;

  Future<void> _inspect() async {
    setState(() => _busy = true);
    try {
      await ref.read(careAutomationProvider.notifier).captureScreenSummary();
    } catch (_) {
      if (mounted) showCareSnack(context, '读取界面摘要失败，请确认无障碍服务已连接。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final screen = widget.lastScreen;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.visibility_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '脱敏界面读取自检',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(56, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: _busy ? null : _inspect,
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('测试读取'),
                ),
              ],
            ),
            if (screen != null) ...[
              const SizedBox(height: 8),
              if (screen.blocked)
                Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 16, color: scheme.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '已触发隐私硬拦截：${screen.reason ?? '当前页面受系统安全策略保护'}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.error),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  screen.available
                      ? '读取正常：识别到 ${screen.nodes.length} 个脱敏界面节点（密码框与敏感页面自动屏蔽）。'
                      : '当前无障碍未返回界面节点，请稍后重试。',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                '可测试无障碍通道是否正常读取当前屏幕，密码输入框与支付/安全应用会自动屏蔽。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({
    required this.ok,
    required this.title,
    required this.okText,
    required this.badText,
    this.optional = false,
    this.action,
  });

  final bool ok;
  final bool optional;
  final String title;
  final String okText;
  final String badText;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = ok
        ? scheme.primary
        : optional
            ? scheme.onSurfaceVariant
            : scheme.error;
    return ListTile(
      leading: Icon(
        ok
            ? Icons.check_circle_rounded
            : optional
                ? Icons.remove_circle_outline_rounded
                : Icons.error_outline_rounded,
        color: color,
      ),
      title: Text(title),
      subtitle: Text(ok ? okText : badText),
      trailing: action,
    );
  }
}

class _RoutineList extends ConsumerWidget {
  const _RoutineList();

  Future<void> _run(BuildContext context, WidgetRef ref, CareRoutine r) async {
    try {
      final result = await ref.read(careRoutineProvider.notifier).runRoutine(r.id);
      if (!context.mounted) return;
      showCareSnack(
        context,
        result.pausedForApproval
            ? '「${r.name}」已暂停，正在等待你确认下一步'
            : result.completed
                ? '「${r.name}」已完成：${result.summary}'
                : result.summary,
      );
    } catch (_) {
      if (context.mounted) showCareSnack(context, '运行失败，请稍后再试。');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(careRoutineProvider);

    return routines.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const CareHintCard(
        icon: Icons.error_outline_rounded,
        title: '暂时无法读取定时任务',
        body: '请稍后再试。',
      ),
      data: (s) {
        if (s.routines.isEmpty) {
          return const CareHintCard(
            icon: Icons.schedule_rounded,
            title: '暂无定时任务',
            body: '直接告诉 Care「每天 21:00 帮我整理待办」即可自动创建，或点右上角新建。',
          );
        }
        return Column(
          children: [
            for (final r in s.routines)
              _RoutineCard(
                key: ValueKey(r.id),
                routine: r,
                runningRoutineId: s.runningRoutineId,
                onRun: () => _run(context, ref, r),
              ),
          ],
        );
      },
    );
  }
}

class _RoutineCard extends ConsumerStatefulWidget {
  const _RoutineCard({
    super.key,
    required this.routine,
    required this.runningRoutineId,
    required this.onRun,
  });

  final CareRoutine routine;
  final String? runningRoutineId;
  final VoidCallback onRun;

  @override
  ConsumerState<_RoutineCard> createState() => _RoutineCardState();
}

class _RoutineCardState extends ConsumerState<_RoutineCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.routine;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8, bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.name,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (r.description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                r.description,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (r.scheduleTimeHHmm != null)
                    Column(
                      children: [
                        Switch(
                          value: r.enabled,
                          onChanged: (v) => ref
                              .read(careRoutineProvider.notifier)
                              .toggleRoutine(r.id, v),
                        ),
                        Text(
                          '每天 ${r.scheduleTimeHHmm}',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: _Tag(
                      text: '${r.steps.length} 个步骤 ${_expanded ? '▲' : '▼'}',
                    ),
                  ),
                  if (r.steps.any((st) => st.isHighRisk))
                    _Tag(text: '含需确认步骤', color: scheme.error),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var idx = 0; idx < r.steps.length; idx++)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: idx == r.steps.length - 1 ? 0 : 6,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${idx + 1}.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  r.steps[idx].description,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              if (r.steps[idx].isHighRisk)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: _Tag(
                                    text: '需确认',
                                    color: scheme.error,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (r.lastRunAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  '上次运行 ${careRelativeTime(r.lastRunAt!)}'
                  '${r.lastRunSummary != null ? ' · ${r.lastRunSummary}' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () async {
                      final ok = await showCareConfirmDialog(
                        context,
                        title: '删除「${r.name}」？',
                        message: '删除后无法恢复。',
                        confirmLabel: '删除',
                        destructive: true,
                      );
                      if (ok) {
                        await ref
                            .read(careRoutineProvider.notifier)
                            .deleteRoutine(r.id);
                      }
                    },
                    child: const Text('删除'),
                  ),
                  const SizedBox(width: 4),
                  widget.runningRoutineId == r.id
                      ? const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        )
                      : FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(64, 40),
                          ),
                          onPressed: widget.runningRoutineId != null
                              ? null
                              : widget.onRun,
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text('运行'),
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

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: c)),
    );
  }
}

class _RoutineDialog extends ConsumerStatefulWidget {
  const _RoutineDialog();

  @override
  ConsumerState<_RoutineDialog> createState() => _RoutineDialogState();
}

class _RoutineDialogState extends ConsumerState<_RoutineDialog> {
  /// Built-in safe local steps the user can compose without coding.
  static const _available = <(String, String)>[
    ('collect_calendar', '读取近期日历安排'),
    ('collect_notices', '读取通知摘要'),
    ('collect_memory', '读取长期记忆'),
    ('generate_evening_briefing', '生成晚间回顾'),
  ];

  final _name = TextEditingController();
  final _desc = TextEditingController();
  final Set<String> _selected = {'collect_calendar'};
  TimeOfDay? _time;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '请给定时任务起个名字');
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _error = '至少选择一个步骤');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    var i = 0;
    final steps = [
      for (final (action, label) in _available)
        if (_selected.contains(action))
          CareRoutineStep(id: 's${++i}', description: label, action: action),
    ];
    try {
      await ref.read(careRoutineProvider.notifier).createRoutine(
            name: _name.text,
            description: _desc.text,
            steps: steps,
            scheduleTimeHHmm: _time == null ? null : careFormatHHmm(_time!),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '创建失败，请稍后再试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建定时任务'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              decoration: InputDecoration(hintText: '名称，例如「周日复盘」', errorText: _error),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              enabled: !_busy,
              decoration: const InputDecoration(hintText: '说明（可选）'),
            ),
            const SizedBox(height: 12),
            Text('步骤', style: Theme.of(context).textTheme.titleSmall),
            for (final (action, label) in _available)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _selected.contains(action),
                title: Text(label),
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                          if (v == true) {
                            _selected.add(action);
                          } else {
                            _selected.remove(action);
                          }
                        }),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime:
                                  _time ?? const TimeOfDay(hour: 21, minute: 0),
                            );
                            if (t != null) setState(() => _time = t);
                          },
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: Text(
                      _time == null
                          ? '定时运行（可选）'
                          : '每天 ${careFormatHHmm(_time!)}',
                    ),
                  ),
                ),
                if (_time != null)
                  IconButton(
                    tooltip: '清除定时',
                    onPressed: _busy ? null : () => setState(() => _time = null),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
              ],
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
          child: const Text('创建'),
        ),
      ],
    );
  }
}
