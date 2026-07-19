import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remote_file_explorer/features/preview/video_preview.dart';

// Video preview tests — focused on resume-position persistence, which is the
// testable logic layer. The video_player + chewie stack requires native plugins
// that can't run in headless widget tests, so we verify the app's own
// readVideoPosition/writeVideoPosition/clearVideoPosition helpers directly
// (PR-83 — these used to reimplement the SharedPreferences key format inline
// instead of calling the production code, so the tests would still pass even
// if that production code were deleted or broke).

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const path1 = '/docs/intro.mp4';
  const path2 = '/media/clip.mkv';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('resume position persistence', () {
    test('saves and reads back a position', () async {
      final prefs = await SharedPreferences.getInstance();
      writeVideoPosition(prefs, path1, 42000);

      expect(readVideoPosition(prefs, path1), 42000);
    });

    test('returns null for a path with no saved position', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(readVideoPosition(prefs, path1), isNull);
    });

    test('different paths store independent positions', () async {
      final prefs = await SharedPreferences.getInstance();
      writeVideoPosition(prefs, path1, 10000);
      writeVideoPosition(prefs, path2, 55000);

      expect(readVideoPosition(prefs, path1), 10000);
      expect(readVideoPosition(prefs, path2), 55000);
    });

    test('clearing a position removes only that path', () async {
      final prefs = await SharedPreferences.getInstance();
      writeVideoPosition(prefs, path1, 10000);
      writeVideoPosition(prefs, path2, 55000);

      clearVideoPosition(prefs, path1);

      expect(readVideoPosition(prefs, path1), isNull);
      expect(readVideoPosition(prefs, path2), 55000);
    });

    test('overwriting a position replaces the old value', () async {
      final prefs = await SharedPreferences.getInstance();
      writeVideoPosition(prefs, path1, 10000);
      writeVideoPosition(prefs, path1, 99000);

      expect(readVideoPosition(prefs, path1), 99000);
    });
  });

  group('kVideoPositionsKey', () {
    test('key constant matches expected value', () {
      expect(kVideoPositionsKey, 'rfe_video_positions');
    });
  });
}
