// PR-62 regression: ShadApp (unlike MaterialApp) doesn't insert a root
// ScaffoldMessenger on its own. This must be tested against the real
// production root (RemoteFileExplorerApp), not a MaterialApp-wrapped
// screen — a MaterialApp shell would mask the exact bug being fixed, since
// MaterialApp provides its own root messenger regardless of what ShadApp
// does (this is what let the bug ship in the first place, per the audit).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/ui/lock_gate.dart';
import 'package:remote_file_explorer/core/update/auto_update.dart';
import 'package:remote_file_explorer/features/settings/update_tile.dart';
import 'package:remote_file_explorer/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'a root ScaffoldMessenger is available under the real app shell',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        ProviderScope(
          // Both touch native platform channels (local notifications) that
          // aren't wired up in a plain widget test — irrelevant to the
          // ScaffoldMessenger question this test asks, so stubbed out
          // rather than pulling in platform-channel mocking infra.
          overrides: [
            updateNotificationTapProvider.overrideWithValue(null),
            backgroundApkDownloadProvider.overrideWith((ref) async {}),
          ],
          child: const RemoteFileExplorerApp(),
        ),
      );
      await tester.pump();

      // LockGate sits inside `home:`, below the ShadApp `builder` that
      // provides the root messenger — the widget under test here, not
      // RemoteFileExplorerApp itself (which is *above* ShadApp).
      final context = tester.element(find.byType(LockGate));
      expect(ScaffoldMessenger.maybeOf(context), isNotNull);
    },
  );
}
