import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/ui/format.dart';

void main() {
  group('formatRelative', () {
    test('just now for under a minute', () {
      final dt = DateTime.now().subtract(const Duration(seconds: 30));
      expect(formatRelative(dt), 'just now');
    });

    test('minutes ago for under an hour', () {
      final dt = DateTime.now().subtract(const Duration(minutes: 5));
      expect(formatRelative(dt), '5m ago');
    });

    test('hours ago for under a day', () {
      final dt = DateTime.now().subtract(const Duration(hours: 3));
      expect(formatRelative(dt), '3h ago');
    });

    test('days ago for under a week', () {
      final dt = DateTime.now().subtract(const Duration(days: 2));
      expect(formatRelative(dt), '2d ago');
    });

    test('falls back to formatDate at 7 days or older', () {
      final dt = DateTime.now().subtract(const Duration(days: 8));
      expect(formatRelative(dt), formatDate(dt));
    });
  });
}
