import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The confirmed "Circular Orbit" hero mockup's rotating dashed ring — a
/// continuously-spinning dashed circle behind the hero host's badge/name/
/// status plate. Pure decoration (`IgnorePointer`), draws its own dashes via
/// [_DashedCirclePainter] since Flutter has no native dashed-circle border.
class HeroOrbitRing extends StatefulWidget {
  const HeroOrbitRing({super.key, required this.diameter});

  final double diameter;

  @override
  State<HeroOrbitRing> createState() => _HeroOrbitRingState();
}

class _HeroOrbitRingState extends State<HeroOrbitRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mockup: `border:1.5px dashed var(--page-ink)` — full-contrast ink, not
    // a muted outline (`onSurface`, not `outlineVariant`).
    final color = Theme.of(context).colorScheme.onSurface;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder:
            (context, _) => Transform.rotate(
              angle: _c.value * 2 * math.pi,
              child: CustomPaint(
                size: Size.square(widget.diameter),
                painter: _DashedCirclePainter(color: color),
              ),
            ),
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter({required this.color});

  final Color color;

  static const _dashCount = 20;
  static const _dashFraction = 0.55; // fraction of each segment that's drawn

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
    final sweepPerDash = (2 * math.pi / _dashCount) * _dashFraction;
    final gapPerDash = (2 * math.pi / _dashCount) - sweepPerDash;
    var angle = 0.0;
    for (var i = 0; i < _dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 1),
        angle,
        sweepPerDash,
        false,
        paint,
      );
      angle += sweepPerDash + gapPerDash;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Positions [actions] at the 4 cardinal points of a circle of [radius]
/// around the center of its parent [Stack] — same trig the HTML mockup used
/// (`idx*90-90` so the first action lands at 12 o'clock).
class HeroActionRing extends StatelessWidget {
  const HeroActionRing({
    super.key,
    required this.radius,
    required this.actions,
  });

  final double radius;
  final List<Widget> actions;

  /// Extra room around the ring so a translated action still lies INSIDE this
  /// widget's own box. Flutter does not hit-test a child painted outside its
  /// parent's bounds: without this the [Stack] shrink-wrapped to one action's
  /// size, every action was translated clear of it, and all four rendered
  /// perfectly while being completely untappable. Sized for the widest action
  /// (58px) plus breathing room.
  static const actionExtent = 68.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: radius * 2 + actionExtent,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < actions.length; i++)
            Builder(
              builder: (context) {
                final deg = i * 90 - 90;
                final rad = deg * math.pi / 180;
                return Transform.translate(
                  offset: Offset(
                    math.cos(rad) * radius,
                    math.sin(rad) * radius,
                  ),
                  child: actions[i],
                );
              },
            ),
        ],
      ),
    );
  }
}
