import 'package:material_ui/material_ui.dart';

/// Care's unified handwritten-script brand mark matching the Android app icon.
class CareAvatar extends StatelessWidget {
  const CareAvatar({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = size * 0.30;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.16),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.10),
            blurRadius: size * 0.24,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(size * 0.06),
        child: Image.asset(
          'assets/icon/care_app_icon.png',
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Center(
            child: Text(
              'Care',
              style: TextStyle(
                fontSize: size * 0.32,
                fontWeight: FontWeight.w800,
                fontStyle: FontStyle.italic,
                color: const Color(0xFF1468F6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small uppercase-ish section header used in settings-style lists.
class CareSectionHeader extends StatelessWidget {
  const CareSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Constrains content width on tablets / foldables while staying full-bleed on phones.
class CareContentWidth extends StatelessWidget {
  const CareContentWidth({super.key, required this.child, this.maxWidth = 760});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

Future<bool> showCareConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                  minimumSize: const Size(64, 40),
                )
              : FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showCareSnack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Parses `HH:mm` into a [TimeOfDay] (falls back to [fallback]).
TimeOfDay careParseHHmm(String raw, {TimeOfDay fallback = const TimeOfDay(hour: 8, minute: 30)}) {
  final parts = raw.split(':');
  if (parts.length != 2) return fallback;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return fallback;
  return TimeOfDay(hour: h, minute: m);
}

String careFormatHHmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Rounded informational card with an icon, used for permission / empty prompts.
class CareHintCard extends StatelessWidget {
  const CareHintCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.tone,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = tone ?? scheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
                  ),
                  if (action != null) ...[
                    const SizedBox(height: 10),
                    action!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
