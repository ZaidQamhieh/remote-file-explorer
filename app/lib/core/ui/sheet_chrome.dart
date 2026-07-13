import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';

/// The small drag handle at the top of a bottom sheet.
class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Hero header for an action sheet or dialog: an optional grabber, a
/// radial-gradient zone tinted by the subject's own colour, an icon badge,
/// title/subtitle, and an optional close button. Originally MetaSheet's
/// file-tap header — shared so every other action surface (host actions,
/// conflict dialogs, etc.) can give its subject the same visual identity
/// instead of a bare text title.
class SheetHero extends StatelessWidget {
  const SheetHero({
    super.key,
    required this.badge,
    required this.title,
    this.subtitle,
    this.tint,
    this.badgeColor,
    this.onClose,
    this.showGrabber = true,
  });

  /// Content shown inside the 56x56 badge box (an [Icon] or similar).
  final Widget badge;
  final String title;
  final String? subtitle;

  /// Colour the radial gradient glow and default badge tint are derived
  /// from. Defaults to [ColorScheme.primary].
  final Color? tint;

  /// Background colour of the badge box. Defaults to [tint] at low alpha.
  final Color? badgeColor;

  /// Shows a close (X) button when non-null.
  final VoidCallback? onClose;
  final bool showGrabber;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heroTint = tint ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.sm,
      ),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topLeft,
          radius: 1.4,
          colors: [
            heroTint.withValues(alpha: 0.28),
            heroTint.withValues(alpha: 0),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showGrabber) ...[
            const SheetGrabber(),
            const SizedBox(height: Spacing.md),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: badgeColor ?? heroTint.withValues(alpha: 0.16),
                  borderRadius: Radii.cardR,
                ),
                alignment: Alignment.center,
                child: badge,
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: Spacing.xs),
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
              if (onClose != null)
                IconButton(
                  icon: const Icon(LucideIcons.x),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: onClose,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single circular gradient quick-action button (the "4 most common taps"
/// row) — Google Photos/WhatsApp file-sheet shape. Colour-code by intent via
/// [gradient] (e.g. blue for view actions, green for downloads/success, red
/// for destructive).
class GradientActionCircle extends StatelessWidget {
  const GradientActionCircle({
    super.key,
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 40,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                ),
                boxShadow: [
                  BoxShadow(
                    color: gradient.last.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Row of [GradientActionCircle]s in a tonal card — the primary-actions
/// strip at the top of an action sheet.
class QuickActionRow extends StatelessWidget {
  const QuickActionRow({super.key, required this.actions});

  final List<GradientActionCircle> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Material (not a plain Container) so the InkResponse splashes inside
    // each GradientActionCircle actually render instead of being hidden
    // behind this row's own background colour.
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: Radii.cardR,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: Spacing.md,
          horizontal: Spacing.xs,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: actions,
        ),
      ),
    );
  }
}

/// A single row inside an [ActionListCard]: icon, label, optional tint
/// (e.g. destructive red), and a trailing chevron.
class ActionListTile extends StatelessWidget {
  const ActionListTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tint;

  /// Overrides the default chevron (e.g. a checkmark for a selected option).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = tint ?? scheme.onSurfaceVariant;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: tint),
      ),
      trailing:
          trailing ??
          Icon(
            LucideIcons.chevronRight,
            size: 16,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
      onTap: onTap,
    );
  }
}

/// Rounded, divided card wrapping a list of rows (typically
/// [ActionListTile]s) — the "everything else" list below a [QuickActionRow],
/// or a picker's whole list of choices.
class ActionListCard extends StatelessWidget {
  const ActionListCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Material (not a plain Container) so each row's ListTile ink splash
    // actually renders instead of being hidden behind this card's own
    // background colour.
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: Radii.cardR,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 56,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}
