import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remote_file_explorer/core/models/app_release.dart';
import 'package:remote_file_explorer/core/update/auto_update.dart';
import 'package:remote_file_explorer/features/settings/update_banner.dart';

import 'l10n_helpers.dart';
import 'shad_test_wrap.dart';

const _release = AppRelease(versionName: '1.5.0', versionCode: 30, size: 1);

Widget _app(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: wrapShad(
    const MaterialApp(
      localizationsDelegates: l10nDelegates,
      home: Scaffold(body: UpdateBanner()),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('UpdateBanner widget', () {
    testWidgets('shows the version and actions when an update is available', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app([latestUpdateProvider.overrideWith((ref) async => _release)]),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Update available · v1.5.0'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Dismiss'), findsOneWidget);
    });

    testWidgets('renders nothing when no update is available', (tester) async {
      await tester.pumpWidget(
        _app([latestUpdateProvider.overrideWith((ref) async => null)]),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Update available'), findsNothing);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('tapping Dismiss hides the banner', (tester) async {
      await tester.pumpWidget(
        _app([latestUpdateProvider.overrideWith((ref) async => _release)]),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Update available'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Dismiss'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Update available'), findsNothing);
    });
  });

  group('DismissedUpdateNotifier', () {
    test('dismiss persists and is monotonic (never lowers)', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(await container.read(dismissedUpdateProvider.future), 0);

      await container.read(dismissedUpdateProvider.notifier).dismiss(10);
      expect(container.read(dismissedUpdateProvider).valueOrNull, 10);

      // A lower code must not lower the stored value.
      await container.read(dismissedUpdateProvider.notifier).dismiss(5);
      expect(container.read(dismissedUpdateProvider).valueOrNull, 10);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('rfe_update_dismissed_code_v1'), 10);
    });
  });
}
