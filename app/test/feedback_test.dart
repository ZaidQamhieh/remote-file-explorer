import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/ui/feedback.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Pumps a button that runs [onTap] with a valid Scaffold/ScaffoldMessenger
/// context, so the feedback helpers have somewhere to show their snackbars.
Future<BuildContext> _harness(
  WidgetTester tester,
  void Function(BuildContext) onTap,
) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) {
            ctx = c;
            return TextButton(
              onPressed: () => onTap(c),
              child: const Text('go'),
            );
          },
        ),
      ),
    ),
  );
  return ctx;
}

void main() {
  testWidgets('showSuccess renders message with a check icon', (tester) async {
    await _harness(tester, (c) => showSuccess(c, 'Done!'));
    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.text('Done!'), findsOneWidget);
    expect(find.byIcon(LucideIcons.circleCheck), findsOneWidget);
  });

  testWidgets('showError offers a Retry that fires the callback', (
    tester,
  ) async {
    var retried = false;
    await _harness(
      tester,
      (c) => showError(c, 'Boom', onRetry: () => retried = true),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle(); // let the floating snackbar finish entering

    expect(find.text('Boom'), findsOneWidget);
    expect(find.byIcon(LucideIcons.circleAlert), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retried, isTrue);
  });

  testWidgets('runWithFeedback returns the value and shows success', (
    tester,
  ) async {
    int? result;
    await _harness(tester, (c) async {
      result = await runWithFeedback<int>(
        c,
        () async => 42,
        success: (v) => 'Got $v',
      );
    });
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(result, 42);
    expect(find.text('Got 42'), findsOneWidget);
  });

  testWidgets('runWithFeedback returns null and shows error on throw', (
    tester,
  ) async {
    Object? sentinel = 'unset';
    await _harness(tester, (c) async {
      sentinel = await runWithFeedback<int>(
        c,
        () async => throw StateError('nope'),
        error: 'Failed',
      );
    });
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(sentinel, isNull);
    expect(find.textContaining('Failed'), findsOneWidget);
  });
}
