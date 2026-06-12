import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/storage/host_store.dart';
import 'package:remote_file_explorer/features/hosts/widgets/host_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

// HostCard widget tests. The card pings the host's `/health` on mount; to
// keep this fast and offline-friendly we point the host at a port nothing is
// listening on (127.0.0.1:1), which fails fast with "connection refused"
// rather than waiting out a timeout — exercising the *offline* render path.
//
// FlutterSecureStorage's platform channel is mocked to return null (no
// stored token/fingerprint), matching a freshly-paired host with nothing
// cached.

const _secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const host = Host(id: 'h1', label: 'main-pc', address: '127.0.0.1:1');

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'rfe_hosts_v1': [jsonEncode(host.toJson())],
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (call) async {
      switch (call.method) {
        case 'read':
          return null;
        case 'write':
        case 'delete':
          return null;
        case 'readAll':
          return <String, String>{};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
  });

  Future<HostStore> buildStore() => HostStore.create();

  testWidgets('offline host renders dimmed with "Offline" status and no gauges',
      (tester) async {
    final store = await buildStore();

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: HostCard(host: host, store: store),
            ),
          ),
        ),
      );

      // Let the /health ping fail (connection refused on 127.0.0.1:1) and
      // the provider chain (hostStoreProvider -> hostByIdProvider -> client)
      // resolve across real event-loop turns.
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });

    expect(find.text('main-pc'), findsOneWidget);
    expect(find.textContaining('Offline'), findsWidgets);

    // Per spec, offline cards dim to 60% opacity EXCEPT the host name — the
    // name `Text` must not sit inside an `Opacity(0.6)` ancestor.
    final nameFinder = find.text('main-pc');
    final dimmedAncestor = find.ancestor(
      of: nameFinder,
      matching: find.byWidgetPredicate(
          (w) => w is Opacity && w.opacity == 0.6),
    );
    expect(dimmedAncestor, findsNothing);

    // No storage gauges for an offline host.
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // Browse stays enabled offline; Search is disabled. FilledButton.icon(...)
    // returns a _FilledButtonWithIcon subclass, so match by predicate instead
    // of an exact find.byType(FilledButton).
    ButtonStyleButton findButton(String label) {
      final finder = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      return tester.widget<ButtonStyleButton>(finder.first);
    }

    expect(findButton('Browse').onPressed, isNotNull);
    expect(findButton('Search').onPressed, isNull);
  });

  testWidgets('renders the quick actions row', (tester) async {
    final store = await buildStore();

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: HostCard(host: host, store: store),
            ),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });

    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
  });
}
