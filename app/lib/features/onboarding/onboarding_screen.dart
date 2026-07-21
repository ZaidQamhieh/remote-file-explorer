import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/gradient_blob_hero.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _kOnboardingKey = 'onboarding_complete';

final onboardingCompleteProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kOnboardingKey) ?? false;
});

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pageCount = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingKey, true);
    ref.invalidate(onboardingCompleteProvider);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLast = _page == _pageCount - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _Page(
                    icon: LucideIcons.monitorSmartphone,
                    title: context.l10n.onboardingWelcomeTitle,
                    body: context.l10n.onboardingWelcomeBody,
                    hero: const _DeviceLinkHero(),
                  ),
                  _Page(
                    icon: LucideIcons.wifi,
                    title: context.l10n.onboardingHowTitle,
                    body: context.l10n.onboardingHowBody,
                  ),
                  _Page(
                    icon: LucideIcons.rocket,
                    title: context.l10n.onboardingReadyTitle,
                    body: context.l10n.onboardingReadyBody,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.md,
                Spacing.lg,
                Spacing.lg,
              ),
              child: Row(
                children: [
                  Row(
                    children: List.generate(
                      _pageCount,
                      (i) => Padding(
                        padding: const EdgeInsets.only(right: Spacing.xs),
                        child: CircleAvatar(
                          radius: 4,
                          backgroundColor:
                              i == _page
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_page > 0)
                    TextButton(
                      onPressed:
                          () => _controller.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          ),
                      child: Text(context.l10n.onboardingBack),
                    ),
                  const SizedBox(width: Spacing.sm),
                  FilledButton(
                    onPressed:
                        isLast
                            ? _finish
                            : () => _controller.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            ),
                    child: Text(
                      isLast
                          ? context.l10n.onboardingGetStarted
                          : context.l10n.onboardingNext,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.icon,
    required this.title,
    required this.body,
    this.hero,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Overrides the default [GradientBlobHero] with a page-specific
  /// illustration (e.g. [_DeviceLinkHero] on the welcome page, matching the
  /// mockup's phone↔PC connector art instead of the generic placeholder).
  final Widget? hero;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          hero ?? GradientBlobHero(icon: icon, size: 140),
          const SizedBox(height: Spacing.xl),
          Text(
            title,
            // Matches ScreenHeader's scale (28px / w700 / -0.5 tracking) so
            // onboarding's headline reads at the same weight as top-level
            // screen titles, even though this page has no AppBar to host
            // ScreenHeader itself.
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.md),
          Text(
            body,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Phone-chip — dashed connector — monitor-chip illustration matching the
/// mockup's welcome-page art exactly (two device chips linked by a dashed
/// line, not an icon-in-a-blob). Static — no animation needed to match this
/// source, unlike [GradientBlobHero].
class _DeviceLinkHero extends StatelessWidget {
  const _DeviceLinkHero();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DeviceChip(
          width: 64,
          height: 88,
          icon: LucideIcons.smartphone,
          iconColor: scheme.primary,
        ),
        const SizedBox(width: Spacing.md2),
        const _DashedLine(),
        const SizedBox(width: Spacing.md2),
        _DeviceChip(
          width: 104,
          height: 74,
          icon: LucideIcons.monitor,
          iconColor: Brand.accent,
        ),
      ],
    );
  }
}

class _DeviceChip extends StatelessWidget {
  const _DeviceChip({
    required this.width,
    required this.height,
    required this.icon,
    required this.iconColor,
  });

  final double width;
  final double height;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Icon(icon, size: height * 0.28, color: iconColor),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 30,
      height: 2,
      child: Row(
        children: List.generate(
          4,
          (i) => Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
              color: scheme.outline,
            ),
          ),
        ),
      ),
    );
  }
}
