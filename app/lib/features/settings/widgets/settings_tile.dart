import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/pressable.dart';

/// The mockup's `.row`: 38x38 `.row-icon` (r-md, tonal square, not a circle),
/// `.row-title`/`.row-sub` (14px/500, 11.5px faint), and a trailing
/// `.switch`/chevron/"value ›" — built raw from the literal CSS (docs/
/// mockup-reference/mockup.css), no `ShadSwitch`. Three shapes:
/// - [SettingsTile.toggle]  — trailing `.switch`, whole row toggles
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
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.15),
              borderRadius: Radii.smR,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11.5,
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
        // Whole row toggles, not just the switch — the switch itself renders
        // no gesture handling of its own, so there's no double-fire to guard
        // against (PR-64's original concern, now structurally impossible).
        return MergeSemantics(
          child: Pressable(onTap: () => _onChanged!(!_value), child: row),
        );
      case _Kind.value:
      case _Kind.nav:
        return Pressable(onTap: onTap, child: row);
    }
  }

  Widget _trailing(BuildContext context, ColorScheme scheme) {
    switch (_kind) {
      case _Kind.toggle:
        return _MockupSwitch(value: _value);
      case _Kind.nav:
        return Icon(
          LucideIcons.chevronRight,
          size: 16,
          color: scheme.onSurfaceVariant,
        );
      case _Kind.value:
        return Row(
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
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
          ],
        );
    }
  }
}

enum _Kind { toggle, value, nav }

/// The mockup's `.switch`: 42x25 pill track (`surface-3` off / `primary` on),
/// 19x19 thumb (`text-faint` off / white on) sliding between `left:2`/
/// `right:2`. Purely decorative — [SettingsTile.toggle] wires the tap on the
/// whole row, not on this widget, so there's nothing here to wire twice.
class _MockupSwitch extends StatelessWidget {
  const _MockupSwitch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: MotionDuration.short,
      width: 42,
      height: 25,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: Radii.stadiumR,
        border: Border.all(
          color: value ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 19,
        height: 19,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: value ? Colors.white : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
