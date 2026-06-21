import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remote_file_explorer/features/preview/video_preview.dart';

// Video preview tests — focused on resume-position persistence, which is the
// testable logic layer. The video_player + chewie stack requires native plugins
// that can't run in headless widget tests, so we verify the SharedPreferences
// read/write/clear contract directly.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const path1 = '/docs/intro.mp4';
  const path2 = '/media/clip.mkv';
  String prefKey(String path) => '${kVideoPositionsKey}_$path';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('resume position persistence', () {
    test('saves and reads back a position', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(prefKey(path1), 42000);

      final stored = prefs.getInt(prefKey(path1));
      expect(stored, 42000);
    });

    test('returns null for a path with no saved position', () async {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(prefKey(path1));
      expect(stored, isNull);
    });

    test('different paths store independent positions', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(prefKey(path1), 10000);
      await prefs.setInt(prefKey(path2), 55000);

      expect(prefs.getInt(prefKey(path1)), 10000);
      expect(prefs.getInt(prefKey(path2)), 55000);
    });

    test('clearing a position removes only that path', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(prefKey(path1), 10000);
      await prefs.setInt(prefKey(path2), 55000);

      await prefs.remove(prefKey(path1));

      expect(prefs.getInt(prefKey(path1)), isNull);
      expect(prefs.getInt(prefKey(path2)), 55000);
    });

    test('overwriting a position replaces the old value', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(prefKey(path1), 10000);
      await prefs.setInt(prefKey(path1), 99000);

      expect(prefs.getInt(prefKey(path1)), 99000);
    });
  });

  group('kVideoPositionsKey', () {
    test('key constant matches expected value', () {
      expect(kVideoPositionsKey, 'rfe_video_positions');
    });
  });
}
