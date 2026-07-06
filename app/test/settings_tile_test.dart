import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:remote_file_explorer/features/settings/widgets/settings_tile.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('toggle variant renders a Switch and reports changes', (
    tester,
  ) async {
    bool? changed;
    await _pump(
      tester,
      SettingsTile.toggle(
        icon: LucideIcons.bell,
        title: 'Transfer notifications',
        value: false,
        onChanged: (v) => changed = v,
      ),
    );
    expect(find.text('Transfer notifications'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    expect(changed, isTrue);
  });

  testWidgets('value variant shows the value and fires onTap', (tester) async {
    var tapped = false;
    await _pump(
      tester,
      SettingsTile.value(
        icon: LucideIcons.palette,
        title: 'Theme',
        value: 'Dark',
        onTap: () => tapped = true,
      ),
    );
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    await tester.tap(find.text('Theme'));
    expect(tapped, isTrue);
  });

  testWidgets('nav variant fires onTap and shows no value text', (
    tester,
  ) async {
    var tapped = false;
    await _pump(
      tester,
      SettingsTile.nav(
        icon: LucideIcons.info,
        title: 'About & Changelog',
        subtitle: "Version info and what's new",
        onTap: () => tapped = true,
      ),
    );
    await tester.tap(find.text('About & Changelog'));
    expect(tapped, isTrue);
  });
}
