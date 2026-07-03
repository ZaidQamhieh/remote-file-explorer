import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/storage/favorites.dart';
import 'package:remote_file_explorer/features/explorer/widgets/favorites_pin_row.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// FavoritesPinRow: horizontal row of "pin" cards for a host's favorited
// folders, shown above the listing at the explorer root (Wave C2 item 6).

const _favorites = [
  Favorite(hostId: 'h1', path: '/root/Documents', label: 'Documents'),
  Favorite(hostId: 'h1', path: '/root/Photos', label: 'Photos'),
];

void main() {
  testWidgets('renders nothing when there are no favorites', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FavoritesPinRow(
            favorites: const [],
            onOpen: (_) {},
            onRemove: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(FavoritesPinRow), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    expect(find.text('Documents'), findsNothing);
  });

  testWidgets('renders one card per favorite', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FavoritesPinRow(
            favorites: _favorites,
            onOpen: (_) {},
            onRemove: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.byIcon(LucideIcons.folder), findsNWidgets(2));
  });

  testWidgets('tapping a card calls onOpen with that favorite', (tester) async {
    Favorite? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FavoritesPinRow(
            favorites: _favorites,
            onOpen: (fav) => opened = fav,
            onRemove: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Photos'));
    await tester.pump();

    expect(opened, isNotNull);
    expect(opened!.path, '/root/Photos');
  });

  testWidgets('long-pressing a card calls onRemove with that favorite', (
    tester,
  ) async {
    Favorite? removed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FavoritesPinRow(
            favorites: _favorites,
            onOpen: (_) {},
            onRemove: (fav) => removed = fav,
          ),
        ),
      ),
    );

    await tester.longPress(find.text('Documents'));
    await tester.pump();

    expect(removed, isNotNull);
    expect(removed!.path, '/root/Documents');
  });
}
