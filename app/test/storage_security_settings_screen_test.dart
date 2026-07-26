import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/settings/settings_controller.dart';
import 'package:remote_file_explorer/core/ui/lock_gate.dart';
import 'package:remote_file_explorer/features/settings/storage_security_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shadcn_ui/shadcn_ui.dart';

import 'l10n_helpers.dart';
import 'shad_test_wrap.dart';

class _FakeAuthenticator implements AppAuthenticator {
  _FakeAuthenticator(this.result);
  final bool result;

  @override
  Future<bool> authenticate(String reason) async => result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('toggling App Lock sets the app default', (tester) async {
    final container = ProviderContainer(
      overrides: [
        appAuthenticatorProvider.overrideWithValue(_FakeAuthenticator(true)),
      ],
    );
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

    await tester.tap(find.byType(ShadSwitch));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).valueOrNull!.app.appLockEnabled,
      isTrue,
    );
  });

  testWidgets('does not enable App Lock when device authentication fails', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        appAuthenticatorProvider.overrideWithValue(_FakeAuthenticator(false)),
      ],
    );
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
    await tester.tap(find.byType(ShadSwitch));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).valueOrNull!.app.appLockEnabled,
      isFalse,
    );
  });
}
