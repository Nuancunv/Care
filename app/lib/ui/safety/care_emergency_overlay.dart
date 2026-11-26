import 'dart:async';

import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Global "Care is operating your phone" takeover bar (AGENTS.md §1.3 / M3).
///
/// Mounted in `MaterialApp.builder` so it floats above every page while an
/// automation step or Routine is running, offering a one-tap emergency stop
/// and a brief confirmation pill once the user takes back control.
class CareEmergencyOverlay extends ConsumerStatefulWidget {
  const CareEmergencyOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CareEmergencyOverlay> createState() => _CareEmergencyOverlayState();
}

class _CareEmergencyOverlayState extends ConsumerState<CareEmergencyOverlay> {
  bool _justStopped = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  Future<void> _stop() async {
    try {
      await ref.read(careAutomationProvider.notifier).emergencyStop();
    } catch (_) {}
    if (!mounted) return;
    _hideTimer?.cancel();
    setState(() => _justStopped = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _justStopped = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final executing =
        ref.watch(careAutomationProvider.select((s) => s.isExecuting));
    final routineRunning = ref.watch(
      careRoutineProvider.select((s) => s.value?.runningRoutineId != null),
    );
    final active = executing || routineRunning;

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 16,
          right: 16,
          top: MediaQuery.paddingOf(context).top + 8,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: active
                ? _TakeoverBar(key: const ValueKey('active'), onStop: _stop)
                : _justStopped
                    ? const _StoppedPill(key: ValueKey('stopped'))
                    : const SizedBox.shrink(key: ValueKey('idle')),
          ),
        ),
      ],
    );
  }
}

class _TakeoverBar extends StatelessWidget {
  const _TakeoverBar({super.key, required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      color: scheme.errorContainer,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Row(
          children: [
            Icon(Icons.touch_app_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Care 正在替你操作',
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
                minimumSize: const Size(64, 40),
              ),
              onPressed: onStop,
              child: const Text('立即停止'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoppedPill extends StatelessWidget {
  const _StoppedPill({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Material(
        elevation: 3,
        color: scheme.secondaryContainer,
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded,
                  size: 18, color: scheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Text(
                '已停止，手机控制权已交还给你',
                style: TextStyle(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
