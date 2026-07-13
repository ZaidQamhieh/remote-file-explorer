import 'package:flutter/material.dart';

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

/// Bottom tab bar matching the Figma design's `BottomNav`: icon + small label,
/// with a short rounded pill above the active tab's icon instead of Material's
/// pill-behind-the-icon indicator. Replaces the stock [NavigationBar] so the
/// 4-tab shell matches the intended look.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AppBottomNavDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
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
      ),
    );
  }
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
