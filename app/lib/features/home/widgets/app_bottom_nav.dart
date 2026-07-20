import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';

/// One tab in [AppBottomNav].
class AppBottomNavDestination {
  const AppBottomNavDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
}

const double _kBarHeight = 76;
const double _kNotchDepth = 14;
const double _kHalfNotchWidth = 40;
const double _kFabDiameter = 48;

/// Bottom tab bar with a curved notch cut into the top edge and a floating
/// "Add computer" button docked in it — a constant action shared across all
/// 4 tabs, not a 5th destination. [destinations] must have exactly 4 entries
/// (2 either side of the notch).
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.onAddPressed,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AppBottomNavDestination> destinations;
  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surface),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _kBarHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _NotchBarPainter(
                    color: scheme.surfaceContainerLow,
                    borderColor: scheme.outlineVariant,
                  ),
                ),
              ),
              Positioned(
                top: _kNotchDepth,
                left: 0,
                right: 0,
                bottom: 0,
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          for (var i = 0; i < 2; i++)
                            Expanded(
                              child: _NavButton(
                                destination: destinations[i],
                                selected: i == selectedIndex,
                                onTap: () => onDestinationSelected(i),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: _kHalfNotchWidth * 2),
                    Expanded(
                      child: Row(
                        children: [
                          for (var i = 2; i < 4; i++)
                            Expanded(
                              child: _NavButton(
                                destination: destinations[i],
                                selected: i == selectedIndex,
                                onTap: () => onDestinationSelected(i),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 2,
                left: 0,
                right: 0,
                child: Center(
                  child: Tooltip(
                    message: 'Add computer',
                    child: InkResponse(
                      onTap: onAddPressed,
                      radius: 32,
                      child: Container(
                        width: _kFabDiameter,
                        height: _kFabDiameter,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Brand.seed, Brand.accent],
                          ),
                          border: Border.all(color: scheme.surface, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Brand.seed.withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          LucideIcons.plus,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fills the bar with a curved notch cut into the top edge, centered —
/// same silhouette as the `curved_navigation_bar` package, sized to
/// [_kHalfNotchWidth]/[_kNotchDepth] so [AppBottomNav]'s Add button nests
/// into it.
class _NotchBarPainter extends CustomPainter {
  const _NotchBarPainter({required this.color, required this.borderColor});

  final Color color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const w = _kHalfNotchWidth;
    const d = _kNotchDepth;
    const c = 20.0; // bezier control-point offset, tunes curve smoothness
    final fillPath =
        Path()
          ..moveTo(0, d)
          ..lineTo(cx - w, d)
          ..cubicTo(cx - w + c, d, cx - w + c, 0, cx, 0)
          ..cubicTo(cx + w - c, 0, cx + w - c, d, cx + w, d)
          ..lineTo(size.width, d)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
    canvas.drawPath(fillPath, Paint()..color = color);

    // Trace just the top edge (curve + flat shoulders) for definition —
    // the surface fill barely differs from the app background otherwise.
    final borderPath =
        Path()
          ..moveTo(0, d)
          ..lineTo(cx - w, d)
          ..cubicTo(cx - w + c, d, cx - w + c, 0, cx, 0)
          ..cubicTo(cx + w - c, 0, cx + w - c, d, cx + w, d)
          ..lineTo(size.width, d);
    canvas.drawPath(
      borderPath,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_NotchBarPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.borderColor != borderColor;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppBottomNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = selected ? scheme.primary : scheme.outline;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 4,
            width: 32,
            child:
                selected
                    ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: Radii.stadiumR,
                      ),
                    )
                    : null,
          ),
          const SizedBox(height: Spacing.xs),
          AnimatedContainer(
            duration: MotionDuration.short,
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md2,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color:
                  selected
                      ? scheme.primary.withValues(alpha: 0.16)
                      : Colors.transparent,
              borderRadius: Radii.stadiumR,
            ),
            child: Icon(
              selected
                  ? (destination.selectedIcon ?? destination.icon)
                  : destination.icon,
              color: tint,
              size: 22,
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            destination.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tint,
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
