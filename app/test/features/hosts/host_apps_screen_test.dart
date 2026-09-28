import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/models/host_app.dart';
import 'package:remote_file_explorer/features/hosts/host_apps_screen.dart';

import '../../l10n_helpers.dart';

const _host = Host(id: 'h1', label: 'Office PC', address: '127.0.0.1:8765');

Widget _screen(HostAppCatalog catalog) {
  return ProviderScope(
    overrides: [
      hostAppsProvider(_host.id).overrideWith((ref) async => catalog),
    ],
    child: MaterialApp(
      localizationsDelegates: l10nDelegates,
      home: const HostAppsScreen(host: _host),
    ),
  );
}

void main() {
  testWidgets(
    'shows host catalog metadata and filters by name or description',
    (tester) async {
      const catalog = HostAppCatalog(
        platform: 'linux',
        launchAllowed: true,
        apps: [
          HostApp(
            id: 'editor',
            name: 'Writer',
            launchable: true,
            description: 'A document editor',
            icon: 'office',
          ),
          HostApp(
            id: 'browser',
            name: 'Web Explorer',
            launchable: true,
            description: 'Browse the internet',
            icon: 'browser',
          ),
        ],
      );
      await tester.pumpWidget(_screen(catalog));
      await tester.pumpAndSettle();

      expect(find.text('Apps found'), findsOneWidget);
      expect(find.text('Linux app catalog'), findsOneWidget);
      expect(find.text('2 apps'), findsOneWidget);
      expect(find.text('A document editor'), findsOneWidget);
      expect(find.text('Browse the internet'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('host-apps-search')),
        'internet',
      );
      await tester.pumpAndSettle();

      expect(find.text('Web Explorer'), findsOneWidget);
      expect(find.text('Writer'), findsNothing);
      expect(find.text('1 match'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear app search'));
      await tester.pumpAndSettle();
      expect(find.text('Writer'), findsOneWidget);
      expect(find.text('Web Explorer'), findsOneWidget);
    },
  );

  testWidgets('shows view-only access and disables Run when launch is denied', (
    tester,
  ) async {
    const catalog = HostAppCatalog(
      platform: 'windows',
      launchAllowed: false,
      apps: [HostApp(id: 'paint', name: 'Paint', launchable: true)],
    );
    await tester.pumpWidget(_screen(catalog));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The host admin allows viewing this app list but has not allowed this device to launch apps.',
      ),
      findsOneWidget,
    );
    final runButton = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Run'), matching: find.byType(FilledButton)),
    );
    expect(runButton.onPressed, isNull);
  });

  testWidgets('shows discovered apps without a supported Run action', (
    tester,
  ) async {
    const catalog = HostAppCatalog(
      platform: 'linux',
      launchAllowed: true,
      apps: [HostApp(id: 'legacy', name: 'Legacy App', launchable: false)],
    );
    await tester.pumpWidget(_screen(catalog));
    await tester.pumpAndSettle();

    expect(find.text('Legacy App'), findsOneWidget);
    expect(
      find.text('Listed, but this app cannot be started remotely.'),
      findsOneWidget,
    );
    final runButton = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Run'), matching: find.byType(FilledButton)),
    );
    expect(runButton.onPressed, isNull);
  });

  testWidgets('shows platform-specific guidance for an empty catalog', (
    tester,
  ) async {
    const catalog = HostAppCatalog(
      platform: 'darwin',
      launchAllowed: true,
      apps: [],
    );
    await tester.pumpWidget(_screen(catalog));
    await tester.pumpAndSettle();

    expect(find.text('macOS app catalog'), findsOneWidget);
    expect(find.text('0 apps'), findsOneWidget);
    expect(find.text('No apps found'), findsOneWidget);
    expect(
      find.text(
        'This computer did not report apps in its supported app catalog.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('provides retry guidance when the catalog cannot be loaded', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hostAppsProvider(_host.id).overrideWith((ref) async {
            throw StateError('offline');
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: l10nDelegates,
          home: const HostAppsScreen(host: _host),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Could not load the app list. Check the connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('explains when app viewing is denied by host permissions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hostAppsProvider(_host.id).overrideWith((ref) async {
            throw AgentApiException(403, 'APP_VIEW_FORBIDDEN', 'denied');
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: l10nDelegates,
          home: const HostAppsScreen(host: _host),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('App access is turned off'), findsOneWidget);
    expect(
      find.text(
        'An admin must enable app access for this device in the computer’s settings.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });
}
