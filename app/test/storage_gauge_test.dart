import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/drive.dart';
import 'package:remote_file_explorer/features/hosts/widgets/storage_gauge.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('usedFraction', () {
    test('computes the used fraction from total and free bytes', () {
      const drive = Drive(path: '/home', totalBytes: 1000, freeBytes: 400);
      expect(usedFraction(drive), closeTo(0.6, 1e-9));
    });

    test('returns 0 when the drive is completely free', () {
      const drive = Drive(path: '/home', totalBytes: 1000, freeBytes: 1000);
      expect(usedFraction(drive), 0.0);
    });

    test('returns 1 when the drive is completely full', () {
      const drive = Drive(path: '/home', totalBytes: 1000, freeBytes: 0);
      expect(usedFraction(drive), 1.0);
    });

    test('clamps to 0 when free exceeds total (bad agent data)', () {
      // used = total - free would be negative; clamping keeps the fraction
      // in range rather than rendering a nonsensical/negative bar.
      const drive = Drive(path: '/home', totalBytes: 1000, freeBytes: 2000);
      expect(usedFraction(drive), 0.0);
    });

    test('returns null when totalBytes is null', () {
      const drive = Drive(path: '/home', freeBytes: 100);
      expect(usedFraction(drive), isNull);
    });

    test('returns null when totalBytes is zero', () {
      const drive = Drive(path: '/home', totalBytes: 0, freeBytes: 0);
      expect(usedFraction(drive), isNull);
    });

    test('returns null when totalBytes is negative', () {
      const drive = Drive(path: '/home', totalBytes: -1, freeBytes: 0);
      expect(usedFraction(drive), isNull);
    });

    test('returns null when freeBytes is null', () {
      const drive = Drive(path: '/home', totalBytes: 1000);
      expect(usedFraction(drive), isNull);
    });
  });

  group('aggregateUsage', () {
    test('returns null for an empty list', () {
      expect(aggregateUsage(const []), isNull);
    });

    test('returns null when no drive has usable capacity', () {
      const drives = [
        Drive(path: '/a'), // no totals
        Drive(path: '/b', totalBytes: 0, freeBytes: 0), // zero total
        Drive(path: '/c', totalBytes: 1000), // free missing
      ];
      expect(aggregateUsage(drives), isNull);
    });

    test('matches usedFraction for a single capacity drive', () {
      const drives = [Drive(path: '/home', totalBytes: 1000, freeBytes: 400)];
      final agg = aggregateUsage(drives)!;
      expect(agg.totalBytes, 1000);
      expect(agg.freeBytes, 400);
      expect(agg.usedFraction, closeTo(0.6, 1e-9));
    });

    test('sums only drives with usable capacity, ignoring the rest', () {
      const drives = [
        Drive(path: '/a', totalBytes: 1000, freeBytes: 250),
        Drive(path: '/b'), // ignored: no totals
        Drive(path: '/c', totalBytes: 3000, freeBytes: 750),
      ];
      final agg = aggregateUsage(drives)!;
      expect(agg.totalBytes, 4000);
      expect(agg.freeBytes, 1000);
      expect(agg.usedFraction, closeTo(0.75, 1e-9)); // used 3000 / total 4000
    });

    test('clamps a per-drive free that exceeds total (bad agent data)', () {
      const drives = [
        Drive(
          path: '/a',
          totalBytes: 1000,
          freeBytes: 2000,
        ), // free capped to 1000
        Drive(path: '/b', totalBytes: 1000, freeBytes: 0),
      ];
      final agg = aggregateUsage(drives)!;
      expect(agg.totalBytes, 2000);
      expect(agg.freeBytes, 1000); // 1000 (capped) + 0
      expect(agg.usedFraction, closeTo(0.5, 1e-9));
    });
  });

  group('StorageGauge widget', () {
    testWidgets('renders free/total label and the mount path', (tester) async {
      const drive = Drive(
        path: '/home',
        totalBytes: 1000 * 1000 * 1000 * 1000, // 1 TB
        freeBytes: 512 * 1000 * 1000 * 1000, // 512 GB
      );
      await tester.pumpWidget(_wrap(const StorageGauge(drive: drive)));

      expect(find.textContaining('free of'), findsOneWidget);
      expect(find.text('/home'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('prefers label over path when present', (tester) async {
      const drive = Drive(
        path: r'C:\',
        label: 'System',
        totalBytes: 1000,
        freeBytes: 500,
      );
      await tester.pumpWidget(_wrap(const StorageGauge(drive: drive)));

      expect(find.text('System'), findsOneWidget);
      expect(find.text(r'C:\'), findsNothing);
    });

    testWidgets('renders nothing when usage cannot be determined', (
      tester,
    ) async {
      const drive = Drive(path: '/mnt/data');
      await tester.pumpWidget(_wrap(const StorageGauge(drive: drive)));

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('/mnt/data'), findsNothing);
    });
  });
}
