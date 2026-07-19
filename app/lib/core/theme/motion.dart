import 'package:flutter/material.dart';

/// Subtle motion helpers. Kept deliberately cheap — a fade-through for screen
/// transitions and a gentle one-shot appear for list rows — so the app feels
/// alive without heavy effects that could stutter on large folders.

/// A fade-through page transition (cross-fade + slight scale), a softer
/// alternative to the default platform slide. Use in place of [MaterialPageRoute]
/// where a calmer transition reads better.
Route<T> fadeThroughPageRoute<T>(
  WidgetBuilder builder, {
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, secondary) => builder(context),
    transitionsBuilder:
        (context, animation, secondary, child) =>
            fadeThroughTransition(animation, child, context: context),
  );
}

/// The cross-fade + slight-scale transition shared by [fadeThroughPageRoute]
/// and [AppPageTransitionsBuilder] — factored out so both stay in sync.
///
/// Returns [child] unchanged, with no fade/scale, when the platform/user
/// reduced-motion accessibility preference is on (PR-65) — pass [context]
/// so this can check it; omitting it (some routes don't have one handy)
/// just keeps the normal transition.
Widget fadeThroughTransition(
  Animation<double> animation,
  Widget child, {
  BuildContext? context,
}) {
  if (context != null && MediaQuery.of(context).disableAnimations) {
    return child;
  }
  final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
  return FadeTransition(
    opacity: curved,
    child: Transform.scale(scale: 0.98 + 0.02 * curved.value, child: child),
  );
}

/// Applies [fadeThroughTransition] to every plain [MaterialPageRoute]/
/// [PageRoute] push app-wide (wired via [ThemeData.pageTransitionsTheme]) so
/// screens that don't explicitly opt into [fadeThroughPageRoute] still get
/// the calmer transition instead of the platform's default slide.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return fadeThroughTransition(animation, child, context: context);
  }
}

/// Wraps a list/grid item so it gently fades and slides up the first time it is
/// built. [index] staggers the start slightly for a cascade; the effect is
/// capped so long lists don't accumulate delay.
class AppearListItem extends StatefulWidget {
  const AppearListItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<AppearListItem> createState() => _AppearListItemState();
}

class _AppearListItemState extends State<AppearListItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  bool _skippedForReducedMotion = false;

  @override
  void initState() {
    super.initState();
    // Stagger by index, capped so deep lists don't pile up delay.
    final delayMs = (widget.index.clamp(0, 8)) * 30;
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted && !_skippedForReducedMotion) _c.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced-motion: skip straight to the settled state instead of
    // fading/sliding in — checked here (not initState) since MediaQuery
    // isn't reliably available that early (PR-65).
    if (!_skippedForReducedMotion && MediaQuery.of(context).disableAnimations) {
      _skippedForReducedMotion = true;
      _c.value = 1.0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
