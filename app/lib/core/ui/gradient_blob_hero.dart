import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Animated two-blob gradient hero — a cheap (no blur/shader, Impeller-off
/// safe) placeholder for onboarding/pairing/empty-state moments until a real
/// Rive asset exists for that slot (see the mockup-parity plan's Foundation
/// phase). Same call site as a plain icon, so swapping in a `.riv` later
/// only changes this widget's body, not its callers.
class GradientBlobHero extends StatefulWidget {
  const GradientBlobHero({
    super.key,
    required this.icon,
    this.size = 160,
    this.colors = const [Brand.seed, Brand.accent],
  });

  final IconData icon;
  final double size;
  final List<Color> colors;

  @override
  State<GradientBlobHero> createState() => _GradientBlobHeroState();
}

class _GradientBlobHeroState extends State<GradientBlobHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value * 2 * math.pi;
          return Stack(
            alignment: Alignment.center,
            children: [
              _blob(t, widget.colors[0], 0),
              _blob(t, widget.colors[1 % widget.colors.length], math.pi),
              child!,
            ],
          );
        },
        child: Icon(widget.icon, size: widget.size * 0.42, color: Colors.white),
      ),
    );
  }

  Widget _blob(double t, Color color, double phase) {
    final dx = math.cos(t + phase) * widget.size * 0.12;
    final dy = math.sin(t + phase) * widget.size * 0.12;
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Container(
        width: widget.size * 0.8,
        height: widget.size * 0.8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
