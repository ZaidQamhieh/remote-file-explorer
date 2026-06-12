import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/features/explorer/widgets/entry_tile.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  final file = Entry(
    name: 'report.pdf',
    path: '/root/report.pdf',
    isDir: false,
    size: 2048,
    mimeType: 'application/pdf',
    modified: DateTime(2024, 3, 5),
  );

  final folder = Entry(
    name: 'Documents',
    path: '/root/Documents',
    isDir: true,
  );

  testWidgets('file entry shows name, size/date subtitle, and no chevron',
      (tester) async {
    await tester.pumpWidget(_wrap(EntryTile(
      entry: file,
      selected: false,
      multiSelect: false,
      onTap: () {},
      onLongPress: () {},
      onSelect: () {},
    )));

    expect(find.text('report.pdf'), findsOneWidget);
    // formatSize(2048) == '2.0 KB', formatDate(2024-03-05) == '2024-03-05'.
    expect(find.textContaining('2.0 KB'), findsOneWidget);
    expect(find.textContaining('2024-03-05'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    // Not in multi-select mode: no checkbox, plain icon leading element.
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byIcon(Icons.picture_as_pdf), findsOneWidget);
  });

  testWidgets('folder entry shows name, chevron, and no subtitle',
      (tester) async {
    await tester.pumpWidget(_wrap(EntryTile(
      entry: folder,
      selected: false,
      multiSelect: false,
      onTap: () {},
      onLongPress: () {},
      onSelect: () {},
    )));

    expect(find.text('Documents'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.folder), findsOneWidget);
    // No size/date subtitle for directories.
    expect(find.textContaining('KB'), findsNothing);
  });

  testWidgets('multiSelect mode shows a checkbox reflecting selected state',
      (tester) async {
    var selectCalls = 0;
    await tester.pumpWidget(_wrap(EntryTile(
      entry: file,
      selected: true,
      multiSelect: true,
      onTap: () {},
      onLongPress: () {},
      onSelect: () => selectCalls++,
    )));

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isTrue);

    await tester.tap(find.byType(Checkbox));
    expect(selectCalls, 1);
  });

  testWidgets('tapping the tile invokes onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(EntryTile(
      entry: folder,
      selected: false,
      multiSelect: false,
      onTap: () => tapped = true,
      onLongPress: () {},
      onSelect: () {},
    )));

    await tester.tap(find.byType(EntryTile));
    expect(tapped, isTrue);
  });
}
