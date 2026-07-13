import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/storage/host_store.dart';
import 'package:remote_file_explorer/features/hosts/widgets/host_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_helpers.dart';

// HostCard widget tests. The card pings the host's `/health` on mount; to
// keep this fast and offline-friendly we point the host at a port nothing is
// listening on (127.0.0.1:1), which fails fast with "connection refused"
// rather than waiting out a timeout — exercising the *offline* render path.
//
// FlutterSecureStorage's platform channel is mocked to return null (no
// stored token/fingerprint), matching a freshly-paired host with nothing
// cached.

const _secureChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

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

  testWidgets(
    'offline host renders dimmed with "Offline" status and no gauges',
    (tester) async {
      final store = await buildStore();

      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: l10nDelegates,
              home: Scaffold(body: HostCard(host: host, store: store)),
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
          (w) => w is Opacity && w.opacity == 0.6,
        ),
      );
      expect(dimmedAncestor, findsNothing);

      // No storage gauges for an offline host — the thin row doesn't render
      // any dashboard content inline.
      expect(find.byType(LinearProgressIndicator), findsNothing);

      // The whole row browses on tap (no separate "Browse" button anymore);
      // Search only appears in the ⋯ sheet while online, so it's simply
      // absent (not disabled) while offline.
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Search'), findsNothing);
    },
  );

  testWidgets('renders the ⋯ sheet with the row actions', (tester) async {
    final store = await buildStore();

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: l10nDelegates,
            home: Scaffold(body: HostCard(host: host, store: store)),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });

    expect(find.byTooltip('More'), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    expect(find.text('main-pc'), findsWidgets); // sheet title + row name
    expect(find.text('Transfers'), findsOneWidget);
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Forget this computer'), findsOneWidget);
    // Offline host (no /system/drives data): Search and Storage are omitted.
    expect(find.text('Search'), findsNothing);
    expect(find.text('Storage'), findsNothing);
  });
}
