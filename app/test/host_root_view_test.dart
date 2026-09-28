import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/agent_settings.dart';
import 'package:remote_file_explorer/core/models/health.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/explorer/host_root_view.dart';
import 'package:remote_file_explorer/features/explorer/explorer_state.dart';

const _host = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

AgentSettings _settings({
  List<String> roots = const [],
  bool accessDenied = false,
}) => AgentSettings(
  roots: roots,
  accessDenied: accessDenied,
  agentName: 'Test agent',
  readOnly: false,
);

Health _health(String os) => Health(
  status: 'ok',
  name: 'Test agent',
  version: '1.0.0',
  os: os,
  readOnly: false,
);

void main() {
  group('allowedRootForPath', () {
    test('returns the most specific containing root', () {
      expect(
        allowedRootForPath(['/share', '/share/photos'], '/share/photos/a.jpg'),
        '/share/photos',
      );
    });

    test('does not treat a sibling prefix as inside the root', () {
      expect(allowedRootForPath(['/share'], '/share-old/a.txt'), isNull);
    });

    test('matches Windows roots case-insensitively', () {
      expect(
        allowedRootForPath(
          [r'C:\Users\Public'],
          r'c:\users\public\Reports\a.pdf',
          windows: true,
        ),
        r'C:\Users\Public',
      );
    });

    test('handles Windows drive roots', () {
      expect(
        allowedRootForPath([r'C:\'], r'C:\Photos\a.jpg', windows: true),
        r'C:\',
      );
    });
  });

  group('buildPathStackWithinRoot', () {
    test('starts at the configured root instead of filesystem root', () {
      expect(buildPathStackWithinRoot('/share', '/share/photos/2026'), [
        '/share',
        '/share/photos',
        '/share/photos/2026',
      ]);
    });

    test('clamps a stale/outside bookmark to the configured root', () {
      expect(buildPathStackWithinRoot('/share', '/etc'), ['/share']);
    });

    test('keeps Windows navigation at its drive jail', () {
      expect(buildPathStackWithinRoot(r'C:\Shared', r'c:\shared\Photos'), [
        r'C:\Shared',
        r'c:\shared\Photos',
      ]);
    });
  });

  testWidgets('restricted host shows only effective shared folders', (
    tester,
  ) async {
    String? selectedRoot;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hostBrowsingSettingsProvider(
            _host.id,
          ).overrideWith((ref) async => _settings(roots: ['/tmp/rfe-share'])),
        ],
        child: MaterialApp(
          home: HostRootView(
            host: _host,
            health: _health('linux'),
            onSelectRoot: (root, _) => selectedRoot = root,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shared folders'), findsOneWidget);
    expect(find.text('/tmp/rfe-share'), findsOneWidget);
    await tester.tap(find.byType(ListTile).first);
    expect(selectedRoot, '/tmp/rfe-share');
  });

  testWidgets('unrestricted Linux host opens filesystem root', (tester) async {
    final selections = <(String, String?)>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hostBrowsingSettingsProvider(
            _host.id,
          ).overrideWith((ref) async => _settings()),
        ],
        child: MaterialApp(
          home: HostRootView(
            host: _host,
            health: _health('linux'),
            onSelectRoot: (root, path) => selections.add((root, path)),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(selections, [('/', null)]);
  });

  testWidgets('saved path opens from its effective jail root', (tester) async {
    final selections = <(String, String?)>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hostBrowsingSettingsProvider(
            _host.id,
          ).overrideWith((ref) async => _settings(roots: ['/tmp/rfe-share'])),
        ],
        child: MaterialApp(
          home: HostRootView(
            host: _host,
            health: _health('linux'),
            initialPath: '/tmp/rfe-share/photos',
            onSelectRoot: (root, path) => selections.add((root, path)),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(selections, [('/tmp/rfe-share', '/tmp/rfe-share/photos')]);
  });

  testWidgets('denied host scope never falls back to unrestricted browse', (
    tester,
  ) async {
    final selections = <(String, String?)>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hostBrowsingSettingsProvider(
            _host.id,
          ).overrideWith((ref) async => _settings(accessDenied: true)),
        ],
        child: MaterialApp(
          home: HostRootView(
            host: _host,
            health: _health('linux'),
            onSelectRoot: (root, path) => selections.add((root, path)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This device has no file access on this computer.'),
      findsOneWidget,
    );
    expect(selections, isEmpty);
  });
}
