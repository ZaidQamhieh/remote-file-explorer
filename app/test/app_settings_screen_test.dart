import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/settings/about_support_settings_screen.dart';
import 'package:remote_file_explorer/features/settings/app_settings_screen.dart';
import 'package:remote_file_explorer/features/settings/appearance_settings_screen.dart';
import 'package:remote_file_explorer/features/settings/file_visibility_screen.dart';
import 'package:remote_file_explorer/features/settings/notifications_settings_screen.dart';
import 'package:remote_file_explorer/features/settings/storage_security_settings_screen.dart';
import 'package:remote_file_explorer/features/settings/transfers_backup_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_helpers.dart';
import 'shad_test_wrap.dart';

// AppSettingsScreen is now a card-grouped 6-row nav matching the mockup's
// tab-settings screen (Preferences / Data / Support sections); the actual
// controls are covered by each sub-screen's own test file.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: wrapShad(
          const MaterialApp(
            localizationsDelegates: l10nDelegates,
            home: AppSettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows all 6 category rows', (tester) async {
    await pump(tester);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Storage & Security'), findsOneWidget);
    expect(find.text('Transfers & Backup'), findsOneWidget);
    expect(find.text('File Visibility'), findsOneWidget);
    expect(find.text('About & Support'), findsOneWidget);
  });

  testWidgets('tapping Appearance pushes AppearanceSettingsScreen', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.byType(AppearanceSettingsScreen), findsOneWidget);
  });

  testWidgets(
    'tapping Transfers & Backup pushes TransfersBackupSettingsScreen',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Transfers & Backup'));
      await tester.pumpAndSettle();
      expect(find.byType(TransfersBackupSettingsScreen), findsOneWidget);
    },
  );

  testWidgets('tapping Notifications pushes NotificationsSettingsScreen', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsSettingsScreen), findsOneWidget);
  });

  testWidgets('tapping File Visibility pushes FileVisibilityScreen', (
    tester,
  ) async {
    await pump(tester);
    await tester.ensureVisible(find.text('File Visibility'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('File Visibility'));
    await tester.pumpAndSettle();
    expect(find.byType(FileVisibilityScreen), findsOneWidget);
  });

  testWidgets(
    'tapping Storage & Security pushes StorageSecuritySettingsScreen',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Storage & Security'));
      await tester.pumpAndSettle();
      expect(find.byType(StorageSecuritySettingsScreen), findsOneWidget);
    },
  );

  testWidgets('tapping About & Support pushes AboutSupportSettingsScreen', (
    tester,
  ) async {
    await pump(tester);
    await tester.ensureVisible(find.text('About & Support'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About & Support'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutSupportSettingsScreen), findsOneWidget);
  });
}
