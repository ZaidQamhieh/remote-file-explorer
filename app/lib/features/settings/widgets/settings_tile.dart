import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';

/// The one uniform settings row. Three shapes:
/// - [SettingsTile.toggle]  — trailing [Switch]
/// - [SettingsTile.value]   — trailing "value ›", whole row tappable (opens a picker)
/// - [SettingsTile.nav]     — trailing bare chevron, whole row pushes a screen
class SettingsTile extends StatelessWidget {
  const SettingsTile.toggle({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.badgeColor,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) : _kind = _Kind.toggle,
       _value = value,
       _onChanged = onChanged,
       valueLabel = null,
       leadingDot = null,
       onTap = null;

  const SettingsTile.value({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.badgeColor,
    required String value,
    this.leadingDot,
    required VoidCallback this.onTap,
  }) : _kind = _Kind.value,
       valueLabel = value,
       _value = false,
       _onChanged = null;

  const SettingsTile.nav({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.badgeColor,
    required VoidCallback this.onTap,
  }) : _kind = _Kind.nav,
       valueLabel = null,
       leadingDot = null,
       _value = false,
       _onChanged = null;

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? valueLabel;
  final Color? leadingDot;
  final VoidCallback? onTap;

  /// Tint for the icon's tonal badge. Defaults to [ColorScheme.onSurfaceVariant]
  /// (a flat neutral icon) when unset, for tiles that don't warrant a category
  /// colour (e.g. a lone toggle with no siblings to distinguish from).
  final Color? badgeColor;
  final _Kind _kind;
  final bool _value;
  final ValueChanged<bool>? _onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = badgeColor ?? scheme.onSurfaceVariant;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.md2 - 2),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          _trailing(context, scheme),
        ],
      ),
    );

    switch (_kind) {
      case _Kind.toggle:
        return row; // Switch itself is the interactive target.
      case _Kind.value:
      case _Kind.nav:
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.chip),
          child: row,
        );
    }
  }

  Widget _trailing(BuildContext context, ColorScheme scheme) {
    switch (_kind) {
      case _Kind.toggle:
        return Switch(value: _value, onChanged: _onChanged);
      case _Kind.nav:
        return Icon(
          LucideIcons.chevronRight,
          size: 20,
          color: scheme.onSurfaceVariant,
        );
      case _Kind.value:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.06),
            borderRadius: Radii.stadiumR,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leadingDot != null) ...[
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: leadingDot,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
              ],
              Text(
                valueLabel!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Icon(
                LucideIcons.chevronRight,
                size: 14,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        );
    }
  }
}

enum _Kind { toggle, value, nav }
