import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../common/care_copy.dart';
import '../common/care_widgets.dart';

/// Watches the native SafetyGate queue and raises a high-priority, non-dismissible
/// approval sheet whenever a request is pending (AGENTS.md §1.3).
///
/// The sheet can only be closed by an explicit 允许 / 拒绝 decision forwarded to
/// the Kotlin `CareSafetyGatePlugin`; there is no bypass path in the UI.
class CareSafetyGateListener extends ConsumerStatefulWidget {
  const CareSafetyGateListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CareSafetyGateListener> createState() =>
      _CareSafetyGateListenerState();
}

class _CareSafetyGateListenerState
    extends ConsumerState<CareSafetyGateListener> {
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(
      careSafetyProvider.select((s) => s.hasPending),
      (_, hasPending) {
        if (hasPending) _scheduleSheet();
      },
      fireImmediately: true,
    );
  }

  void _scheduleSheet() {
    if (_sheetOpen) return;
    _sheetOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _sheetOpen = false;
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        useSafeArea: true,
        useRootNavigator: true,
        builder: (_) => const CareSafetyApprovalSheet(),
      );
      _sheetOpen = false;
      if (mounted && ref.read(careSafetyProvider).hasPending) _scheduleSheet();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class CareSafetyApprovalSheet extends ConsumerStatefulWidget {
  const CareSafetyApprovalSheet({super.key});

  @override
  ConsumerState<CareSafetyApprovalSheet> createState() =>
      _CareSafetyApprovalSheetState();
}

class _CareSafetyApprovalSheetState
    extends ConsumerState<CareSafetyApprovalSheet> {
  bool _busy = false;
  bool _closing = false;

  Future<void> _resolve(
    String id, {
    required bool approve,
    bool alsoEmergencyStop = false,
  }) async {
    setState(() => _busy = true);
    final ctrl = ref.read(careSafetyProvider.notifier);
    var ok = false;
    try {
      ok = approve ? await ctrl.approve(id) : await ctrl.deny(id);
      if (alsoEmergencyStop) {
        try {
          await ref.read(careAutomationProvider.notifier).emergencyStop();
        } catch (_) {}
      }
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      showCareSnack(context, '没能提交你的选择，请再试一次。');
    } else if (alsoEmergencyStop) {
      showCareSnack(context, '已拒绝并触发紧急停止，手机已交还给你。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(careSafetyProvider.select((s) => s.pending));
    if (pending.isEmpty) {
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
      return const SizedBox(height: 120);
    }

    final req = pending.first;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final createdAt = req.createdAtMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(req.createdAtMs)
        : null;

    final isHighRisk = req.riskLevel.toUpperCase() == 'L2';
    final isAutomationAction = req.action.startsWith('accessibility_') ||
        req.action == 'payment_action' ||
        req.action == 'system_settings_write';

    return PopScope(
      canPop: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.shield_outlined,
                      color: scheme.onErrorContainer),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '需要你确认',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Care 想要${careSafetyActionLabel(req.action)}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _SafetyPill(
                  icon: Icons.verified_user_outlined,
                  text: isHighRisk ? '高风险 · 单次授权' : '需确认操作',
                  bg: isHighRisk ? scheme.errorContainer : scheme.secondaryContainer,
                  fg: isHighRisk ? scheme.onErrorContainer : scheme.onSecondaryContainer,
                ),
                _SafetyPill(
                  icon: Icons.timer_outlined,
                  text: '仅本次有效，60 秒内自动过期',
                  bg: scheme.surfaceContainerHighest,
                  fg: scheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    req.summary.isNotEmpty
                        ? req.summary
                        : careSafetyActionLabel(req.action),
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                  if ((req.target ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _MetaRow(icon: Icons.apps_rounded, text: '涉及：${req.target}'),
                  ],
                  if (createdAt != null) ...[
                    const SizedBox(height: 6),
                    _MetaRow(
                      icon: Icons.schedule_rounded,
                      text: '发起时间 ${careClockTime(createdAt)}',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              pending.length > 1
                  ? '只有你同意后才会执行。另外还有 ${pending.length - 1} 项等待确认。'
                  : '只有你同意后才会执行。拒绝不会影响正常聊天。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _busy ? null : () => _resolve(req.id, approve: false),
                    child: const Text('拒绝'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed:
                        _busy ? null : () => _resolve(req.id, approve: true),
                    child: const Text('允许执行'),
                  ),
                ),
              ],
            ),
            if (isAutomationAction) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  onPressed: _busy
                      ? null
                      : () => _resolve(
                            req.id,
                            approve: false,
                            alsoEmergencyStop: true,
                          ),
                  icon: const Icon(Icons.pan_tool_outlined, size: 18),
                  label: const Text('拒绝并紧急停止后续操作'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SafetyPill extends StatelessWidget {
  const _SafetyPill({
    required this.icon,
    required this.text,
    required this.bg,
    required this.fg,
  });

  final IconData icon;
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
        ),
      ],
    );
  }
}
