import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/storage/view_prefs.dart';
import 'package:remote_file_explorer/features/explorer/thumbnail_image.dart';
import 'package:remote_file_explorer/features/explorer/widgets/entry_tile.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Returns no thumbnail bytes, so the row falls back to the category icon —
/// enough to assert the [ThumbnailImage] is wired in without hitting a host.
class _FakeAgentClient extends AgentClient {
  _FakeAgentClient()
    : super(const Host(id: 'h1', label: 'PC', address: '127.0.0.1:1'));

  @override
  Future<Uint8List?> thumbnail(String remotePath, {int size = 256}) async =>
      null;
}

void main() {
  final file = Entry(
    name: 'report.pdf',
    path: '/root/report.pdf',
    isDir: false,
    size: 2048,
    mimeType: 'application/pdf',
    modified: DateTime(2024, 3, 5),
  );

  final image = Entry(
    name: 'photo.jpg',
    path: '/root/photo.jpg',
    isDir: false,
    size: 4096,
    mimeType: 'image/jpeg',
    modified: DateTime(2024, 3, 6),
  );

  final folder = Entry(name: 'Documents', path: '/root/Documents', isDir: true);

  testWidgets('file entry shows name, size/date subtitle, and no chevron', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        EntryTile(
          entry: file,
          selected: false,
          multiSelect: false,
          onTap: () {},
          onLongPress: () {},
          onSelect: () {},
        ),
      ),
    );

    expect(find.text('report.pdf'), findsOneWidget);
    // formatSize(2048) == '2.0 KB', formatDate(2024-03-05) == '2024-03-05'.
    expect(find.textContaining('2.0 KB'), findsOneWidget);
    expect(find.textContaining('2024-03-05'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    // Not in multi-select mode: no checkbox, plain icon leading element.
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byIcon(Icons.picture_as_pdf), findsOneWidget);
  });

  testWidgets('image entry with a client renders a ThumbnailImage in the row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        EntryTile(
          entry: image,
          client: _FakeAgentClient(),
          selected: false,
          multiSelect: false,
          onTap: () {},
          onLongPress: () {},
          onSelect: () {},
        ),
      ),
    );

    expect(find.byType(ThumbnailImage), findsOneWidget);
  });

  testWidgets(
    'image entry without a client keeps the plain icon (no thumbnail)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          EntryTile(
            entry: image,
            selected: false,
            multiSelect: false,
            onTap: () {},
            onLongPress: () {},
            onSelect: () {},
          ),
        ),
      );

      expect(find.byType(ThumbnailImage), findsNothing);
    },
  );

  testWidgets(
    'non-image entry with a client does not render a ThumbnailImage',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          EntryTile(
            entry: file,
            client: _FakeAgentClient(),
            selected: false,
            multiSelect: false,
            onTap: () {},
            onLongPress: () {},
            onSelect: () {},
          ),
        ),
      );

      expect(find.byType(ThumbnailImage), findsNothing);
    },
  );

  testWidgets('folder entry shows name, chevron, and no subtitle', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        EntryTile(
          entry: folder,
          selected: false,
          multiSelect: false,
          onTap: () {},
          onLongPress: () {},
          onSelect: () {},
        ),
      ),
    );

    expect(find.text('Documents'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.byIcon(Icons.folder), findsOneWidget);
    // No size/date subtitle for directories.
    expect(find.textContaining('KB'), findsNothing);
  });

  testWidgets('multiSelect mode shows a checkbox reflecting selected state', (
    tester,
  ) async {
    var selectCalls = 0;
    await tester.pumpWidget(
      _wrap(
        EntryTile(
          entry: file,
          selected: true,
          multiSelect: true,
          onTap: () {},
          onLongPress: () {},
          onSelect: () => selectCalls++,
        ),
      ),
    );

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isTrue);

    await tester.tap(find.byType(Checkbox));
    expect(selectCalls, 1);
  });

  testWidgets('tapping the tile invokes onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        EntryTile(
          entry: folder,
          selected: false,
          multiSelect: false,
          onTap: () => tapped = true,
          onLongPress: () {},
          onSelect: () {},
        ),
      ),
    );

    await tester.tap(find.byType(EntryTile));
    expect(tapped, isTrue);
  });

  group('density variants', () {
    testWidgets('comfortable density shows name and meta on separate lines '
        'with a 40dp leading container', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EntryTile(
            entry: file,
            selected: false,
            multiSelect: false,
            density: EntryDensity.comfortable,
            onTap: () {},
            onLongPress: () {},
            onSelect: () {},
          ),
        ),
      );

      // Name and meta render as two separate Text widgets, stacked in a
      // Column (comfortable = two-line row).
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.textContaining('2.0 KB'), findsOneWidget);

      // Leading icon container sized 40dp in comfortable density.
      final size = tester.getSize(
        find
            .descendant(
              of: find.byType(EntryTile),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(size.width, 40);
      expect(size.height, 40);
    });

    testWidgets('compact density shows name and meta inline on one row', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          EntryTile(
            entry: file,
            selected: false,
            multiSelect: false,
            density: EntryDensity.compact,
            onTap: () {},
            onLongPress: () {},
            onSelect: () {},
          ),
        ),
      );

      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.textContaining('2.0 KB'), findsOneWidget);
      // Compact density lays name + meta out in a Row rather than a Column.
      final rowFinder = find.descendant(
        of: find.byType(EntryTile),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Row &&
              w.children.length == 3 &&
              w.children.any((c) => c is Expanded),
        ),
      );
      expect(rowFinder, findsWidgets);
    });

    testWidgets('selected tile paints primaryContainer behind it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          EntryTile(
            entry: folder,
            selected: true,
            multiSelect: false,
            onTap: () {},
            onLongPress: () {},
            onSelect: () {},
          ),
        ),
      );

      final materials = tester.widgetList<Material>(
        find.descendant(
          of: find.byType(EntryTile),
          matching: find.byType(Material),
        ),
      );
      final scheme =
          Theme.of(tester.element(find.byType(EntryTile))).colorScheme;
      expect(materials.any((m) => m.color == scheme.primaryContainer), isTrue);
    });
  });
}
