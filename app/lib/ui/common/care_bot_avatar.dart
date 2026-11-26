import 'dart:math' as math;

import 'package:care_app/state/care_providers.dart';
import 'package:material_ui/material_ui.dart';

/// Animated cute 3D-shaded Bot avatar adapted from Fei-Craft/DS-Bot's
/// `characters.js` character family (Apache-2.0; see THIRD_PARTY_NOTICES.md).
///
/// Features gentle idle floating/breathing, periodic natural blinking eyes,
/// livelier motion while thinking/streaming, and tap-to-pet happy smiling eyes.
class CareBotAvatar extends StatefulWidget {
  const CareBotAvatar({
    super.key,
    required this.shape,
    this.colorKey = 'sky',
    this.size = 40,
    this.active = false,
    this.interactive = true,
  });

  factory CareBotAvatar.forBot(
    CareBotProfile bot, {
    Key? key,
    double size = 40,
    bool active = false,
    bool interactive = true,
  }) =>
      CareBotAvatar(
        key: key,
        shape: bot.avatarShape == 'care' ? 'acorn' : bot.avatarShape,
        colorKey: bot.avatarColor,
        size: size,
        active: active,
        interactive: interactive,
      );

  final String shape;
  final String colorKey;
  final double size;
  final bool active;
  final bool interactive;

  @override
  State<CareBotAvatar> createState() => _CareBotAvatarState();
}

class _CareBotAvatarState extends State<CareBotAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  bool _happy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _pet() {
    if (!widget.interactive || widget.shape == 'care') return;
    setState(() => _happy = true);
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _happy = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final effectiveShape = widget.shape == 'care' ? 'acorn' : widget.shape;

    final disableAnim = MediaQuery.disableAnimationsOf(context);
    if (disableAnim && _ctrl.isAnimating) {
      _ctrl.stop();
    } else if (!disableAnim && !_ctrl.isAnimating) {
      _ctrl.repeat();
    }

    final (Color top, Color bottom) = _paletteFor(widget.colorKey);
    final child = SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          final bobAmp = widget.active ? 2.4 : 1.2;
          final dy = math.sin(t * math.pi * 2) * bobAmp;
          final blink = !_happy && (t > 0.88 && t < 0.94);
          final glanceX = math.sin(t * math.pi * 2) * 0.025;
          final scaleY = _happy ? 0.93 : 1.0;

          return Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(
              scaleY: scaleY,
              child: CustomPaint(
                painter: _MascotPainter(
                  shape: effectiveShape,
                  topColor: top,
                  bottomColor: bottom,
                  blink: blink,
                  happy: _happy,
                  glanceX: glanceX,
                ),
              ),
            ),
          );
        },
      ),
    );

    if (!widget.interactive) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _pet,
      child: child,
    );
  }

  static (Color, Color) _paletteFor(String key) => switch (key) {
        'blue' => (const Color(0xFF5FA8FF), const Color(0xFF256CE8)),
        'mint' => (const Color(0xFF69D5B8), const Color(0xFF2FA889)),
        'violet' => (const Color(0xFFA794FF), const Color(0xFF6B5CE7)),
        'coral' => (const Color(0xFFFF9A8B), const Color(0xFFF06A6A)),
        'amber' => (const Color(0xFFFFCA6C), const Color(0xFFF09638)),
        _ => (const Color(0xFF7BC8FF), const Color(0xFF3992F6)), // sky
      };
}

class _MascotPainter extends CustomPainter {
  const _MascotPainter({
    required this.shape,
    required this.topColor,
    required this.bottomColor,
    required this.blink,
    required this.happy,
    required this.glanceX,
  });

  final String shape;
  final Color topColor;
  final Color bottomColor;
  final bool blink;
  final bool happy;
  final double glanceX;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Offset.zero & size;
    final bodyPath = _buildShapePath(shape, s);

    // 1. Soft 3D gradient body
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [topColor, bottomColor],
      ).createShader(rect);
    canvas.drawPath(bodyPath, fillPaint);

    // 2. Subtle top-left specular sheen & bottom-right depth shade (DS-Bot 3-layer feel)
    canvas.save();
    canvas.clipPath(bodyPath);
    canvas.drawCircle(
      Offset(s * 0.30, s * 0.24),
      s * 0.28,
      Paint()..color = Colors.white.withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      Offset(s * 0.78, s * 0.86),
      s * 0.44,
      Paint()..color = Colors.black.withValues(alpha: 0.08),
    );
    canvas.restore();

    // 3. Expressive tilted capsule eyes (DS-Bot style) or happy upturned arcs
    final eyeColor = Colors.white.withValues(alpha: 0.95);
    final gx = glanceX * s;
    final leftEye = Offset(s * 0.42 + gx, s * 0.50);
    final rightEye = Offset(s * 0.62 + gx, s * 0.47);
    final eyeW = s * 0.085;
    final eyeH = blink ? s * 0.025 : s * 0.17;

    if (happy) {
      final arcPaint = Paint()
        ..color = eyeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.8, s * 0.055)
        ..strokeCap = StrokeCap.round;
      for (final c in [leftEye, rightEye]) {
        final arc = Path()
          ..moveTo(c.dx - eyeW * 0.7, c.dy + s * 0.02)
          ..quadraticBezierTo(c.dx, c.dy - s * 0.06, c.dx + eyeW * 0.7, c.dy + s * 0.02);
        canvas.drawPath(arc, arcPaint);
      }
    } else {
      final eyePaint = Paint()..color = eyeColor;
      for (final c in [leftEye, rightEye]) {
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(-0.16);
        final rrect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: eyeW, height: eyeH),
          Radius.circular(eyeW / 2),
        );
        canvas.drawRRect(rrect, eyePaint);
        canvas.restore();
      }
    }
  }

  static Path _buildShapePath(String shape, double s) {
    final cx = s / 2;
    final cy = s / 2;
    switch (shape) {
      case 'star':
        final p = Path();
        const points = 5;
        final outerR = s * 0.46;
        final innerR = s * 0.28;
        for (var i = 0; i < points * 2; i++) {
          final r = i.isEven ? outerR : innerR;
          final a = -math.pi / 2 + (i * math.pi / points);
          final x = cx + math.cos(a) * r;
          final y = cy + math.sin(a) * r;
          if (i == 0) {
            p.moveTo(x, y);
          } else {
            p.lineTo(x, y);
          }
        }
        p.close();
        return p;

      case 'moon':
        return Path()
          ..addRRect(
            RRect.fromRectAndCorners(
              Rect.fromLTWH(s * 0.14, s * 0.10, s * 0.72, s * 0.80),
              topLeft: Radius.circular(s * 0.42),
              topRight: Radius.circular(s * 0.42),
              bottomLeft: Radius.circular(s * 0.24),
              bottomRight: Radius.circular(s * 0.42),
            ),
          );

      case 'kitty':
        final p = Path()
          ..moveTo(s * 0.22, s * 0.36)
          ..lineTo(s * 0.20, s * 0.12)
          ..quadraticBezierTo(s * 0.22, s * 0.08, s * 0.28, s * 0.12)
          ..lineTo(s * 0.42, s * 0.24)
          ..quadraticBezierTo(s * 0.50, s * 0.21, s * 0.58, s * 0.24)
          ..lineTo(s * 0.72, s * 0.12)
          ..quadraticBezierTo(s * 0.78, s * 0.08, s * 0.80, s * 0.12)
          ..lineTo(s * 0.78, s * 0.36)
          ..cubicTo(s * 0.90, s * 0.50, s * 0.88, s * 0.86, s * 0.50, s * 0.88)
          ..cubicTo(s * 0.12, s * 0.86, s * 0.10, s * 0.50, s * 0.22, s * 0.36)
          ..close();
        return p;

      case 'bunny':
        final p = Path()
          ..addOval(Rect.fromCenter(center: Offset(s * 0.36, s * 0.24), width: s * 0.18, height: s * 0.38))
          ..addOval(Rect.fromCenter(center: Offset(s * 0.62, s * 0.22), width: s * 0.18, height: s * 0.38))
          ..addOval(Rect.fromCenter(center: Offset(s * 0.50, s * 0.60), width: s * 0.72, height: s * 0.62));
        return p;

      case 'wave':
        return Path()
          ..moveTo(s * 0.16, s * 0.52)
          ..cubicTo(s * 0.14, s * 0.14, s * 0.84, s * 0.12, s * 0.84, s * 0.52)
          ..lineTo(s * 0.84, s * 0.78)
          ..quadraticBezierTo(s * 0.72, s * 0.90, s * 0.60, s * 0.78)
          ..quadraticBezierTo(s * 0.50, s * 0.90, s * 0.40, s * 0.78)
          ..quadraticBezierTo(s * 0.28, s * 0.90, s * 0.16, s * 0.78)
          ..close();

      case 'gumdrop':
        return Path()
          ..moveTo(s * 0.50, s * 0.10)
          ..cubicTo(s * 0.78, s * 0.18, s * 0.88, s * 0.56, s * 0.82, s * 0.76)
          ..cubicTo(s * 0.76, s * 0.90, s * 0.24, s * 0.90, s * 0.18, s * 0.76)
          ..cubicTo(s * 0.12, s * 0.56, s * 0.22, s * 0.18, s * 0.50, s * 0.10)
          ..close();

      case 'blossom':
        final p = Path();
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3;
          p.addOval(
            Rect.fromCircle(
              center: Offset(cx + math.cos(a) * s * 0.20, cy + math.sin(a) * s * 0.20),
              radius: s * 0.24,
            ),
          );
        }
        return p;

      default: // acorn / squircle
        return Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(s * 0.12, s * 0.12, s * 0.76, s * 0.76),
              Radius.circular(s * 0.30),
            ),
          );
    }
  }

  @override
  bool shouldRepaint(covariant _MascotPainter old) =>
      old.shape != shape ||
      old.topColor != topColor ||
      old.bottomColor != bottomColor ||
      old.blink != blink ||
      old.happy != happy ||
      old.glanceX != glanceX;
}
