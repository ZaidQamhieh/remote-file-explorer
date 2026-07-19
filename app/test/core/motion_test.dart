// Tests for PR-65: the shared motion helpers must honor the platform/user
// reduced-motion accessibility preference (MediaQuery.disableAnimations).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/theme/motion.dart';

// Deliberately not MaterialApp: it introduces its own page-route
// FadeTransitions that would pollute find.byType(FadeTransition) below.
Widget _withReducedMotion(bool reduced, Widget child) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduced),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

void main() {
  group('fadeThroughTransition', () {
    testWidgets('returns the child unchanged when reduced motion is on', (
      tester,
    ) async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 260),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _withReducedMotion(
          true,
          Builder(
            builder:
                (context) => fadeThroughTransition(
                  controller,
                  const Text('content'),
                  context: context,
                ),
          ),
        ),
      );

      expect(find.byType(FadeTransition), findsNothing);
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('applies the fade/scale transition normally otherwise', (
      tester,
    ) async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 260),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _withReducedMotion(
          false,
          Builder(
            builder:
                (context) => fadeThroughTransition(
                  controller,
                  const Text('content'),
                  context: context,
                ),
          ),
        ),
      );

      expect(find.byType(FadeTransition), findsOneWidget);
    });
  });

  group('AppearListItem', () {
    testWidgets(
      'jumps straight to fully-visible when reduced motion is on, no delay',
      (tester) async {
        await tester.pumpWidget(
          _withReducedMotion(
            true,
            const AppearListItem(index: 0, child: Text('row')),
          ),
        );
        // Flush the stagger-delay timer so it doesn't leak past the test,
        // even though it's a no-op once reduced motion already skipped the
        // animation straight to its end value.
        await tester.pump(const Duration(milliseconds: 400));

        final fade = tester.widget<FadeTransition>(find.byType(FadeTransition));
        expect(fade.opacity.value, 1.0);
      },
    );
  });
}
