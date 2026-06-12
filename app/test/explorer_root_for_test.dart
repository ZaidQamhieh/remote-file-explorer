import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/health.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/explorer/drives_view.dart';
import 'package:remote_file_explorer/features/explorer/explorer_screen.dart';
import 'package:remote_file_explorer/features/hosts/widgets/host_card.dart';

// `explorerRootFor` decides which root screen HostCard's "Browse" action
// opens, based on the most recent `/health` response. This is the
// windows-vs-everything-else routing decision from Wave C2 item 5: Windows
// hosts get a drive list (since `/` isn't meaningful there); everything else
// (including offline hosts, where `health` is null) keeps the existing
// `/`-rooted explorer.

const _host = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

Health _health(String os) => Health(
      status: 'ok',
      name: 'agent',
      version: '1.0.0',
      os: os,
      readOnly: false,
    );

void main() {
  group('explorerRootFor', () {
    test('Windows host opens the drive list', () {
      expect(explorerRootFor(_health('windows'), _host), isA<DrivesView>());
    });

    test('Windows os string is matched case-insensitively', () {
      expect(explorerRootFor(_health('Windows'), _host), isA<DrivesView>());
      expect(explorerRootFor(_health('WINDOWS'), _host), isA<DrivesView>());
    });

    test('non-Windows host opens the root-rooted explorer', () {
      expect(explorerRootFor(_health('linux'), _host), isA<ExplorerScreen>());
      expect(explorerRootFor(_health('darwin'), _host), isA<ExplorerScreen>());
    });

    test('unknown OS (offline / no health yet) falls back to the explorer',
        () {
      expect(explorerRootFor(null, _host), isA<ExplorerScreen>());
      expect(explorerRootFor(_health(''), _host), isA<ExplorerScreen>());
    });

    test('ExplorerScreen defaults to "/" root for non-Windows hosts', () {
      final screen = explorerRootFor(_health('linux'), _host) as ExplorerScreen;
      expect(screen.rootPath, '/');
      expect(screen.host, _host);
    });

    test('DrivesView is built for the given host', () {
      final view = explorerRootFor(_health('windows'), _host) as DrivesView;
      expect(view.host, _host);
    });
  });
}
