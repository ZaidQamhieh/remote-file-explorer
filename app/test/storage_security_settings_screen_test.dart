import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:remote_file_explorer/core/settings/settings_controller.dart';
import 'package:remote_file_explorer/features/settings/storage_security_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_helpers.dart';
import 'shad_test_wrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('toggling App Lock sets the app default', (tester) async {
    // Stub device-auth support — real local_auth has no platform
    // implementation in a headless test (PR-18's preflight would otherwise
    // always refuse and the toggle would never actually flip).
    isDeviceAuthSupportedCheck = () async => true;
    addTearDown(
      () =>
          isDeviceAuthSupportedCheck =
              () => LocalAuthentication().isDeviceSupported(),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: wrapShad(
          const MaterialApp(
            localizationsDelegates: l10nDelegates,
            home: StorageSecuritySettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).valueOrNull!.app.appLockEnabled,
      isFalse,
    );

    await tester.tap(find.byType(AnimatedContainer));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).valueOrNull!.app.appLockEnabled,
      isTrue,
    );
  });
}
