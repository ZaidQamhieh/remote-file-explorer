import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/explorer/command_palette.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'shad_test_wrap.dart';

void main() {
  group('CommandPalette', () {
    testWidgets('shows all actions', (tester) async {
      await tester.pumpWidget(
        wrapShad(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => ElevatedButton(
                      onPressed:
                          () => CommandPalette.show(
                            context,
                            actions: [
                              PaletteAction(
                                label: 'Search',
                                icon: Icons.search,
                                onTap: () {},
                              ),
                              PaletteAction(
                                label: 'Refresh',
                                icon: Icons.refresh,
                                onTap: () {},
                              ),
                              PaletteAction(
                                label: 'Trash',
                                icon: Icons.delete_outline,
                                onTap: () {},
                              ),
                            ],
                          ),
                      child: const Text('Open'),
                    ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Trash'), findsOneWidget);
    });

    testWidgets('filters actions by query', (tester) async {
      await tester.pumpWidget(
        wrapShad(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => ElevatedButton(
                      onPressed:
                          () => CommandPalette.show(
                            context,
                            actions: [
                              PaletteAction(
                                label: 'Search',
                                icon: Icons.search,
                                onTap: () {},
                              ),
                              PaletteAction(
                                label: 'Refresh',
                                icon: Icons.refresh,
                                onTap: () {},
                              ),
                            ],
                          ),
                      child: const Text('Open'),
                    ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);

      // Type filter
      await tester.enterText(find.byType(ShadInput), 'sea');
      await tester.pump();

      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Refresh'), findsNothing);
    });

    testWidgets('tapping an action closes dialog and fires callback', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        wrapShad(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => ElevatedButton(
                      onPressed:
                          () => CommandPalette.show(
                            context,
                            actions: [
                              PaletteAction(
                                label: 'Search',
                                icon: Icons.search,
                                onTap: () => tapped = true,
                              ),
                            ],
                          ),
                      child: const Text('Open'),
                    ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
      // Dialog should be dismissed
      expect(find.byType(CommandPalette), findsNothing);
    });

    testWidgets('empty filter shows all actions', (tester) async {
      await tester.pumpWidget(
        wrapShad(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => ElevatedButton(
                      onPressed:
                          () => CommandPalette.show(
                            context,
                            actions: [
                              PaletteAction(
                                label: 'Search',
                                icon: Icons.search,
                                onTap: () {},
                              ),
                              PaletteAction(
                                label: 'Refresh',
                                icon: Icons.refresh,
                                onTap: () {},
                              ),
                            ],
                          ),
                      child: const Text('Open'),
                    ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Type and then clear
      await tester.enterText(find.byType(ShadInput), 'sea');
      await tester.pump();
      expect(find.text('Refresh'), findsNothing);

      await tester.enterText(find.byType(ShadInput), '');
      await tester.pump();
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
    });

    testWidgets('filter is case-insensitive', (tester) async {
      await tester.pumpWidget(
        wrapShad(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => ElevatedButton(
                      onPressed:
                          () => CommandPalette.show(
                            context,
                            actions: [
                              PaletteAction(
                                label: 'Search',
                                icon: Icons.search,
                                onTap: () {},
                              ),
                              PaletteAction(
                                label: 'Refresh',
                                icon: Icons.refresh,
                                onTap: () {},
                              ),
                            ],
                          ),
                      child: const Text('Open'),
                    ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(ShadInput), 'SEARCH');
      await tester.pump();

      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Refresh'), findsNothing);
    });

    testWidgets('no match shows empty list', (tester) async {
      await tester.pumpWidget(
        wrapShad(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => ElevatedButton(
                      onPressed:
                          () => CommandPalette.show(
                            context,
                            actions: [
                              PaletteAction(
                                label: 'Search',
                                icon: Icons.search,
                                onTap: () {},
                              ),
                            ],
                          ),
                      child: const Text('Open'),
                    ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(ShadInput), 'zzzzz');
      await tester.pump();

      expect(find.byType(ListTile), findsNothing);
    });
  });
}
