import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/home/home_state.dart';

// Regression coverage for the tab-bar restructure's back-button and
// multi-select-bar-overlap fix. See home_shell.dart's HomeShell.build for
// how these pure decisions get wired to real ExplorerScreen state.
void main() {
  group('shouldHideTabBar', () {
    test('hides only on the Files tab while multi-select is active', () {
      expect(
        shouldHideTabBar(selectedIndex: 1, explorerMultiSelect: true),
        isTrue,
      );
    });

    test('stays visible on the Files tab without multi-select', () {
      expect(
        shouldHideTabBar(selectedIndex: 1, explorerMultiSelect: false),
        isFalse,
      );
    });

    test('stays visible on other tabs even if multiSelect is (stale) true', () {
      expect(
        shouldHideTabBar(selectedIndex: 0, explorerMultiSelect: true),
        isFalse,
      );
    });
  });

  group('shouldReturnToServersOnBack', () {
    test('Servers tab: never redirect (normal exit-app back behavior)', () {
      expect(
        shouldReturnToServersOnBack(selectedIndex: 0, showsExplorerRoot: false),
        isFalse,
      );
    });

    test('Transfers tab: always redirect', () {
      expect(
        shouldReturnToServersOnBack(selectedIndex: 2, showsExplorerRoot: false),
        isTrue,
      );
    });

    test('Settings tab: always redirect', () {
      expect(
        shouldReturnToServersOnBack(selectedIndex: 3, showsExplorerRoot: false),
        isTrue,
      );
    });

    test('Files tab, no active host (empty state): redirect', () {
      expect(
        shouldReturnToServersOnBack(selectedIndex: 1, showsExplorerRoot: false),
        isTrue,
      );
    });

    test('Files tab, DrivesView (Windows host, no path): redirect', () {
      // DrivesView never intercepts back itself.
      expect(
        shouldReturnToServersOnBack(selectedIndex: 1, showsExplorerRoot: false),
        isTrue,
      );
    });

    test(
      'Files tab, ExplorerScreen at folder root, no multi-select: redirect',
      () {
        expect(
          shouldReturnToServersOnBack(
            selectedIndex: 1,
            showsExplorerRoot: true,
            explorerAtRoot: true,
            explorerMultiSelect: false,
          ),
          isTrue,
        );
      },
    );

    test(
      'Files tab, browsing a subfolder: defer to ExplorerScreen (no redirect)',
      () {
        expect(
          shouldReturnToServersOnBack(
            selectedIndex: 1,
            showsExplorerRoot: true,
            explorerAtRoot: false,
            explorerMultiSelect: false,
          ),
          isFalse,
        );
      },
    );

    test(
      'Files tab, multi-select active at root: defer to ExplorerScreen (no redirect)',
      () {
        expect(
          shouldReturnToServersOnBack(
            selectedIndex: 1,
            showsExplorerRoot: true,
            explorerAtRoot: true,
            explorerMultiSelect: true,
          ),
          isFalse,
        );
      },
    );
  });
}
