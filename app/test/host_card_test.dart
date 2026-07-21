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
import 'shad_test_wrap.dart';

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

      // Per spec, offline cards dim the whole card (mockup opacity:.55) —
      // the host name sits inside that same dimmed subtree, unlike the old
      // hero card which kept the name at full opacity.
      final nameFinder = find.text('main-pc');
      final dimmedAncestor = find.ancestor(
        of: nameFinder,
        matching: find.byWidgetPredicate(
          (w) => w is Opacity && w.opacity == 0.55,
        ),
      );
      expect(dimmedAncestor, findsOneWidget);

      // No storage bar for an offline host.
      expect(find.byType(LinearProgressIndicator), findsNothing);

      // The gear (Settings) button is replaced by the "Offline" badge —
      // there's no settings shortcut on a card that can't be reached.
      expect(find.byTooltip('Settings'), findsNothing);
    },
  );

  testWidgets('long-press opens the forget-device confirmation', (
    tester,
  ) async {
    final store = await buildStore();

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: l10nDelegates,
            // ShadDialog is inserted into the root Navigator's overlay, above
            // the Scaffold subtree — wrap the whole app (via `builder`), not
            // just the card, so the dialog also finds a ShadTheme ancestor.
            builder: (context, child) => wrapShad(child!),
            home: Scaffold(body: HostCard(host: host, store: store)),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });

    await tester.longPress(find.text('main-pc'));
    await tester.pumpAndSettle();

    expect(find.text('Forget this computer?'), findsOneWidget);
  });
}
