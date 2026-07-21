import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Drop-in [FilledButton] replacement matching the mockup's `.btn-primary`
/// exactly: a 135° gradient fill (not a flat Material solid) plus a soft
/// colour-tinted glow shadow — the mockup's actual primary-CTA look, which a
/// flat [FilledButton] doesn't reproduce.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.gradient = Brand.primaryGradient,
    this.glowColor = Brand.seed,
    this.icon,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final Gradient gradient;
  final Color glowColor;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w600,
    );

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: Radii.stadiumR,
          gradient: gradient,
          boxShadow:
              disabled
                  ? null
                  : [
                    BoxShadow(
                      color: glowColor.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: Radii.stadiumR,
          child: InkWell(
            borderRadius: Radii.stadiumR,
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.sm + 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    IconTheme(
                      data: const IconThemeData(color: Colors.white, size: 18),
                      child: icon!,
                    ),
                    const SizedBox(width: Spacing.sm),
                  ],
                  DefaultTextStyle(style: textStyle!, child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
