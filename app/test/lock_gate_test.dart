import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/ui/lock_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

// LockGate reads `appLockEnabled` from settingsProvider, an AsyncNotifier
// backed by SharedPreferences — it isn't loaded synchronously at widget
// creation. LockGate.initState() used to call _tryUnlock() immediately,
// which read the not-yet-loaded settings as "app lock off" and unlocked
// the app before the real (persisted) value ever loaded — the lock never
// showed on a cold start no matter what the setting actually was.
void main() {
  testWidgets('shows the lock screen on cold start when appLockEnabled is true '
      '(does not race the async settings load)', (tester) async {
    SharedPreferences.setMockInitialValues({'app.appLockEnabled': true});

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: LockGate(child: Text('unlocked content'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Locked'), findsOneWidget);
    expect(find.text('unlocked content'), findsNothing);
  });

  testWidgets('shows the child immediately when appLockEnabled is false', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app.appLockEnabled': false});

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: LockGate(child: Text('unlocked content'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('unlocked content'), findsOneWidget);
    expect(find.text('Locked'), findsNothing);
  });
}
