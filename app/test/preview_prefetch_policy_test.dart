import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/preview/preview.dart';

// Unit tests for the pure network-aware prefetch gate (S4) that decides
// whether `_preloadNeighbours` actually fetches neighbour bytes.

void main() {
  group('shouldPreloadOnCellular', () {
    test('preloads on Wi-Fi/ethernet/unknown regardless of the setting', () {
      expect(
        shouldPreloadOnCellular(isCellular: false, settingEnabled: false),
        isTrue,
      );
      expect(
        shouldPreloadOnCellular(isCellular: false, settingEnabled: true),
        isTrue,
      );
    });

    test('skips on cellular when the setting is off (default)', () {
      expect(
        shouldPreloadOnCellular(isCellular: true, settingEnabled: false),
        isFalse,
      );
    });

    test('preloads on cellular when the user opted in', () {
      expect(
        shouldPreloadOnCellular(isCellular: true, settingEnabled: true),
        isTrue,
      );
    });
  });
}
