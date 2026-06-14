import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/ui/state_views.dart';

void main() {
  testWidgets('EmptyFolderView shows message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: EmptyFolderView())),
    );
    expect(find.textContaining('empty'), findsOneWidget);
  });

  testWidgets('ErrorRetryCard calls onRetry', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorRetryCard(message: 'boom', onRetry: () => tapped = true),
        ),
      ),
    );
    expect(find.text('boom'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(tapped, isTrue);
  });

  testWidgets('OfflineBanner shows offline text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OfflineBanner())),
    );
    expect(find.textContaining('Offline'), findsOneWidget);
  });
}
