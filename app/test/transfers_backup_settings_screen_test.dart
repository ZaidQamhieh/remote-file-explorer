import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/settings/settings_controller.dart';
import 'package:remote_file_explorer/features/settings/transfers_backup_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('toggling Compress downloads on cellular sets the app default', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: l10nDelegates,
          home: TransfersBackupSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      container
          .read(settingsProvider)
          .valueOrNull!
          .app
          .compressDownloadsOnCellular,
      isTrue,
    );

    await tester.tap(find.text('Compress downloads on cellular'));
    await tester.pumpAndSettle();

    expect(
      container
          .read(settingsProvider)
          .valueOrNull!
          .app
          .compressDownloadsOnCellular,
      isFalse,
    );
  });
}
