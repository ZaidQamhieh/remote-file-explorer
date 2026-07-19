import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/settings/widgets/settings_tile.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'shad_test_wrap.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(wrapShad(MaterialApp(home: Scaffold(body: child))));

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
    await tester.tap(find.byType(ShadSwitch));
    expect(changed, isTrue);
  });

  testWidgets('toggle variant: tapping the switch fires onChanged exactly once '
      '(PR-64 regression -- the row and the switch both wire onTap to the '
      'same callback, matching Flutter\'s own SwitchListTile pattern; a tap '
      'landing on the switch must not double-fire through both)', (
    tester,
  ) async {
    var callCount = 0;
    await _pump(
      tester,
      SettingsTile.toggle(
        icon: LucideIcons.bell,
        title: 'Transfer notifications',
        value: false,
        onChanged: (v) => callCount++,
      ),
    );
    await tester.tap(find.byType(ShadSwitch));
    expect(callCount, 1);
  });

  testWidgets(
    'toggle variant: tapping the row label (not just the switch) also '
    'toggles -- PR-64\'s "full 48dp target", not just the small switch',
    (tester) async {
      var callCount = 0;
      await _pump(
        tester,
        SettingsTile.toggle(
          icon: LucideIcons.bell,
          title: 'Transfer notifications',
          value: false,
          onChanged: (v) => callCount++,
        ),
      );
      await tester.tap(find.text('Transfer notifications'));
      expect(callCount, 1);
    },
  );

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
