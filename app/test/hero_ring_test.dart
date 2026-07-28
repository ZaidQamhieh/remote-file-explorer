import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/hosts/widgets/hero_ring.dart';

// Regression test for a bug that shipped looking perfect: HeroActionRing's
// Stack shrink-wrapped to one action's size, so every action was translated
// outside its parent's bounds. Flutter paints those children but refuses to
// hit-test them — on a real device all four ring actions were dead, while
// widget tests that only asserted on rendered text still passed.
//
// tester.tap() hit-tests at the widget's real coordinates and fails when
// nothing there routes back to it, so this catches exactly that.
void main() {
  testWidgets('every cardinal action is actually tappable where it renders', (
    tester,
  ) async {
    // Make a missed hit-test an outright failure, not a console warning.
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

    final tapped = <String>[];
    const labels = ['North', 'East', 'South', 'West'];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  HeroActionRing(
                    radius: 76,
                    actions: [
                      for (final label in labels)
                        GestureDetector(
                          onTap: () => tapped.add(label),
                          child: SizedBox(
                            width: 58,
                            height: 34,
                            child: Center(child: Text(label)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    for (final label in labels) {
      await tester.tap(find.text(label));
    }
    await tester.pump();

    expect(tapped, labels);
  });
}
