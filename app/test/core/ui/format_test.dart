import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/ui/format.dart';

void main() {
  group('formatDuration', () {
    test('null and zero render 0:00', () {
      expect(formatDuration(null), '0:00');
      expect(formatDuration(Duration.zero), '0:00');
    });

    test('seconds are zero-padded, minutes are not', () {
      expect(formatDuration(const Duration(seconds: 7)), '0:07');
      expect(formatDuration(const Duration(minutes: 3, seconds: 42)), '3:42');
    });

    test('shows an hours field once past an hour', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 5, seconds: 9)),
        '1:05:09',
      );
    });

    test('negative durations clamp to 0:00', () {
      expect(formatDuration(const Duration(seconds: -5)), '0:00');
    });
  });

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
