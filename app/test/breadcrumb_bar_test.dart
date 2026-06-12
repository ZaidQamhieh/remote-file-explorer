import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/explorer/widgets/breadcrumb_bar.dart';

// BreadcrumbBar collapse-logic tests.
//
// `collapsedCrumbIndices` is the pure function deciding which head-ancestor
// crumbs collapse behind a "…" menu chip. The root (index 0) and the tail
// (current directory + its immediate ancestors) always stay visible.

void main() {
  group('collapsedCrumbIndices', () {
    test('returns empty when the stack fits within maxVisible', () {
      expect(collapsedCrumbIndices(1, maxVisible: 4), isEmpty);
      expect(collapsedCrumbIndices(4, maxVisible: 4), isEmpty);
    });

    test('collapses middle ancestors when the stack exceeds maxVisible', () {
      // stack: /, home, zaid, Documents, Photos, 2026 (length 6)
      // maxVisible=4 -> visible tail count = 3 -> visible = [0, 3, 4, 5]
      expect(collapsedCrumbIndices(6, maxVisible: 4), [1, 2]);
    });

    test('collapsed range grows with deeper stacks', () {
      expect(collapsedCrumbIndices(8, maxVisible: 4), [1, 2, 3, 4]);
    });

    test('one entry over the limit collapses exactly one crumb', () {
      // length 5, maxVisible 4 -> visible tail = 3 -> visible = [0, 2, 3, 4]
      expect(collapsedCrumbIndices(5, maxVisible: 4), [1]);
    });

    test('root (index 0) is never in the collapsed range', () {
      for (final length in [5, 6, 10, 20]) {
        final collapsed = collapsedCrumbIndices(length, maxVisible: 4);
        expect(collapsed.contains(0), isFalse);
      }
    });

    test('last index (current directory) is never collapsed', () {
      for (final length in [5, 6, 10, 20]) {
        final collapsed = collapsedCrumbIndices(length, maxVisible: 4);
        expect(collapsed.contains(length - 1), isFalse);
      }
    });

    test('collapsed range is contiguous starting at index 1', () {
      final collapsed = collapsedCrumbIndices(10, maxVisible: 4);
      expect(collapsed.first, 1);
      for (var i = 1; i < collapsed.length; i++) {
        expect(collapsed[i], collapsed[i - 1] + 1);
      }
    });

    test('custom maxVisible of 1 still always shows the current directory',
        () {
      // With maxVisible=1, visibleTailCount=0, firstVisibleTail=length ->
      // collapsed = 1..length-1 (root + everything up to but excluding the
      // current dir collapse... last index stays visible regardless).
      final collapsed = collapsedCrumbIndices(4, maxVisible: 1);
      expect(collapsed.contains(3), isFalse);
    });
  });

  group('crumbLabel', () {
    test('root is "/"', () {
      expect(crumbLabel(['/'], 0), '/');
    });

    test('non-root segments use the final path component', () {
      final stack = ['/', '/home', '/home/zaid'];
      expect(crumbLabel(stack, 1), 'home');
      expect(crumbLabel(stack, 2), 'zaid');
    });

    test('handles Windows-style backslash paths', () {
      final stack = [r'C:\', r'C:\Users', r'C:\Users\zaid'];
      expect(crumbLabel(stack, 1), 'Users');
      expect(crumbLabel(stack, 2), 'zaid');
    });
  });

  group('copyPathToClipboard', () {
    testWidgets('copies the path and shows a confirmation snackbar',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    copyPathToClipboard(context, '/home/zaid/Documents'),
                child: const Text('copy'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(find.textContaining('/home/zaid/Documents'), findsOneWidget);
    });
  });
}
