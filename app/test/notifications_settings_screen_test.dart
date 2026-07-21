import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/settings/settings_controller.dart';
import 'package:remote_file_explorer/features/settings/notifications_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_helpers.dart';
import 'shad_test_wrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('toggling Weekly storage digest sets the app default', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: wrapShad(
          const MaterialApp(
            localizationsDelegates: l10nDelegates,
            home: NotificationsSettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).valueOrNull!.app.weeklyDigestEnabled,
      isFalse,
    );

    // The whole tile is tappable (MergeSemantics + InkWell wrapping title +
    // switch), matching the mockup's "Weekly activity digest" wording.
    await tester.tap(find.text('Weekly activity digest'));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).valueOrNull!.app.weeklyDigestEnabled,
      isTrue,
    );
  });
}
