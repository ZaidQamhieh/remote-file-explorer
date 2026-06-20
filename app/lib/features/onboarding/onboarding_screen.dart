import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/tokens.dart';

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
                    icon: Icons.devices_rounded,
                    title: context.l10n.onboardingWelcomeTitle,
                    body: context.l10n.onboardingWelcomeBody,
                  ),
                  _Page(
                    icon: Icons.wifi_rounded,
                    title: context.l10n.onboardingHowTitle,
                    body: context.l10n.onboardingHowBody,
                  ),
                  _Page(
                    icon: Icons.rocket_launch_rounded,
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
                      onPressed: () => _controller.previousPage(
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
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: scheme.primary),
          const SizedBox(height: Spacing.xl),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.md),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
