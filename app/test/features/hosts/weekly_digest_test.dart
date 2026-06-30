import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/hosts/weekly_digest.dart';

void main() {
  group('shouldShowDigest', () {
    final now = DateTime(2026, 7, 1);

    test('true when never shown before', () {
      expect(shouldShowDigest(null, now), isTrue);
    });

    test('false when shown less than 7 days ago', () {
      final lastShown = now.subtract(const Duration(days: 3));
      expect(shouldShowDigest(lastShown, now), isFalse);
    });

    test('true when shown exactly 7 days ago', () {
      final lastShown = now.subtract(const Duration(days: 7));
      expect(shouldShowDigest(lastShown, now), isTrue);
    });

    test('true when shown more than 7 days ago', () {
      final lastShown = now.subtract(const Duration(days: 10));
      expect(shouldShowDigest(lastShown, now), isTrue);
    });
  });

  group('buildDigestSummary', () {
    const desktop = (
      totalBytes: 1000 * 1024 * 1024 * 1024,
      freeBytes: 340 * 1024 * 1024 * 1024,
      usedFraction: 0.66,
    );

    test('no previous snapshot shows current state without a delta', () {
      final summary = buildDigestSummary({'Desktop-PC': desktop}, {});
      expect(summary, 'Desktop-PC: 340.00 GB free');
    });

    test('free space decreased — shows a negative delta', () {
      const previous = (
        totalBytes: 1000 * 1024 * 1024 * 1024,
        freeBytes: 341 * 1024 * 1024 * 1024 + 200 * 1024 * 1024,
        usedFraction: 0.66,
      );
      final summary = buildDigestSummary(
        {'Desktop-PC': desktop},
        {'Desktop-PC': previous},
      );
      expect(summary, contains('Desktop-PC: 340.00 GB free (-'));
      expect(summary, contains('this week)'));
    });

    test('free space increased — shows a positive delta', () {
      const previous = (
        totalBytes: 1000 * 1024 * 1024 * 1024,
        freeBytes: 300 * 1024 * 1024 * 1024,
        usedFraction: 0.7,
      );
      final summary = buildDigestSummary(
        {'Desktop-PC': desktop},
        {'Desktop-PC': previous},
      );
      expect(summary, 'Desktop-PC: 340.00 GB free (+40.00 GB this week)');
    });

    test('multiple hosts join with a middle dot, mixed delta/no-delta', () {
      const laptop = (
        totalBytes: 256 * 1024 * 1024 * 1024,
        freeBytes: 89 * 1024 * 1024 * 1024,
        usedFraction: 0.65,
      );
      final summary = buildDigestSummary({
        'Desktop-PC': desktop,
        'Laptop': laptop,
      }, {});
      expect(summary, 'Desktop-PC: 340.00 GB free · Laptop: 89.00 GB free');
    });

    test('empty current map returns an empty string', () {
      expect(buildDigestSummary({}, {}), '');
    });
  });
}
