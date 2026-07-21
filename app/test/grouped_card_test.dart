import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/ui/grouped_card.dart';

void main() {
  testWidgets('GroupedCard renders its children inside a rounded card', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GroupedCard(children: [Text('row 1'), Text('row 2')]),
      ),
    );

    expect(find.text('row 1'), findsOneWidget);
    expect(find.text('row 2'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    final decorated = tester.widget<Container>(
      find
          .ancestor(of: find.text('row 1'), matching: find.byType(Container))
          .first,
    );
    expect((decorated.decoration as BoxDecoration).border, isNotNull);
  });

  testWidgets('SectionLabel uppercases its title', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SectionLabel('active hosts')),
    );

    expect(find.text('ACTIVE HOSTS'), findsOneWidget);
  });
}
