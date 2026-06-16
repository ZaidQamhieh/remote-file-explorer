# Storage Insights Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated "Storage" screen (reached from the host-card ⋯ menu) showing an across-all-drives aggregate total plus per-drive gauges, reusing existing widgets and the existing `/system/drives` data.

**Architecture:** Pure client-side Flutter/Riverpod. A new pure helper `aggregateUsage` sums capacity across drives; a new `StorageInsightsScreen` watches the existing `drivesProvider` and renders a total card + a `StorageGauge` list; the host-card overflow menu gains an online-only "Storage" entry. No agent, OpenAPI, or agent-redeploy work.

**Tech Stack:** Flutter, flutter_riverpod, flutter_test. Reuses `Drive`, `StorageGauge`/`usedFraction`, `drivesProvider`, `state_views`, `format.formatSize`, theme `tokens`.

**Spec:** `docs/superpowers/specs/2026-06-16-storage-insights-design.md`

**Working dir for all commands:** `~/Storage/Projects/remote-file-explorer/app`

---

### Task 1: `aggregateUsage` pure helper

**Files:**
- Modify: `app/lib/features/hosts/widgets/storage_gauge.dart` (add function near `usedFraction`)
- Test: `app/test/storage_gauge_test.dart` (add a new `group`)

- [ ] **Step 1: Write the failing tests**

Add this group to `app/test/storage_gauge_test.dart` (inside `main()`, after the existing `usedFraction` group):

```dart
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
        Drive(path: '/a', totalBytes: 1000, freeBytes: 2000), // free capped to 1000
        Drive(path: '/b', totalBytes: 1000, freeBytes: 0),
      ];
      final agg = aggregateUsage(drives)!;
      expect(agg.totalBytes, 2000);
      expect(agg.freeBytes, 1000); // 1000 (capped) + 0
      expect(agg.usedFraction, closeTo(0.5, 1e-9));
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/storage_gauge_test.dart`
Expected: FAIL — compile error, `aggregateUsage` is not defined.

- [ ] **Step 3: Implement the helper**

Add to `app/lib/features/hosts/widgets/storage_gauge.dart`, immediately after the `usedFraction` function (before the `StorageGauge` class):

```dart
/// Aggregate used/free/total across every drive in [drives] that reports real
/// capacity (`totalBytes != null && totalBytes > 0 && freeBytes != null`).
///
/// Returns `null` when no drive has usable capacity, so callers can render an
/// empty state instead of a meaningless zero bar. A per-drive `freeBytes` that
/// exceeds its `totalBytes` (bad agent data) is capped to the total so it can't
/// inflate the aggregate free beyond capacity — mirroring [usedFraction]'s
/// clamping contract.
({int totalBytes, int freeBytes, double usedFraction})? aggregateUsage(
  List<Drive> drives,
) {
  var sumTotal = 0;
  var sumFree = 0;
  var any = false;
  for (final drive in drives) {
    final total = drive.totalBytes;
    final free = drive.freeBytes;
    if (total == null || total <= 0 || free == null) continue;
    any = true;
    sumTotal += total;
    sumFree += free > total ? total : free;
  }
  if (!any || sumTotal <= 0) return null;
  final used = sumTotal - sumFree;
  return (
    totalBytes: sumTotal,
    freeBytes: sumFree,
    usedFraction: (used / sumTotal).clamp(0.0, 1.0),
  );
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/storage_gauge_test.dart`
Expected: PASS — all `usedFraction` and `aggregateUsage` tests green.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/hosts/widgets/storage_gauge.dart app/test/storage_gauge_test.dart
git commit -m "feat(app): aggregateUsage helper for cross-drive storage totals"
```

---

### Task 2: `StorageInsightsScreen`

**Files:**
- Create: `app/lib/features/hosts/storage_insights_screen.dart`
- Test: `app/test/storage_insights_screen_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Create `app/test/storage_insights_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remote_file_explorer/core/models/drive.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/ui/state_views.dart';
import 'package:remote_file_explorer/features/explorer/drives_view.dart'
    show drivesProvider;
import 'package:remote_file_explorer/features/hosts/storage_insights_screen.dart';

const _host = Host(id: 'h1', label: 'Test PC', address: '100.64.0.1');

Widget _app(Override override) => ProviderScope(
      overrides: [override],
      child: const MaterialApp(home: StorageInsightsScreen(host: _host)),
    );

void main() {
  testWidgets('renders the total card and a gauge per capacity drive',
      (tester) async {
    await tester.pumpWidget(
      _app(
        drivesProvider('h1').overrideWith((ref) async => const [
              Drive(path: '/', totalBytes: 1000, freeBytes: 400, isOS: true),
              Drive(path: '/data', totalBytes: 2000, freeBytes: 1000),
            ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All drives'), findsOneWidget);
    // One bar for the total card + one per capacity drive (2) = 3.
    expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
    expect(find.textContaining('free of'), findsWidgets);
  });

  testWidgets('shows the empty view when no drive has capacity',
      (tester) async {
    await tester.pumpWidget(
      _app(
        drivesProvider('h1')
            .overrideWith((ref) async => const [Drive(path: '/mnt')]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(EmptyFolderView), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('shows an error card when drives fail to load', (tester) async {
    await tester.pumpWidget(
      _app(
        drivesProvider('h1')
            .overrideWith((ref) async => throw Exception('boom')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorRetryCard), findsOneWidget);
    expect(find.textContaining('Could not load storage'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/storage_insights_screen_test.dart`
Expected: FAIL — `storage_insights_screen.dart` does not exist (import error).

- [ ] **Step 3: Implement the screen**

Create `app/lib/features/hosts/storage_insights_screen.dart`:

```dart
/// A focused storage view for a single host: an across-all-drives aggregate
/// total plus a per-drive [StorageGauge] list. Reached from the host card's
/// ⋯ menu. Reuses the existing `drivesProvider` (`/system/drives`); no agent
/// work. Drives without usable capacity are excluded from the total and
/// skipped by [StorageGauge].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/host.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/format.dart';
import '../../core/ui/state_views.dart';
import '../explorer/drives_view.dart' show drivesProvider;
import 'widgets/storage_gauge.dart';

class StorageInsightsScreen extends ConsumerWidget {
  const StorageInsightsScreen({super.key, required this.host});

  final Host host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drivesAsync = ref.watch(drivesProvider(host.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${host.label} · Storage',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: drivesAsync.when(
        loading: () => const ListingSkeleton(),
        error: (e, _) => ErrorRetryCard(
          message: 'Could not load storage: $e',
          onRetry: () => ref.invalidate(drivesProvider(host.id)),
        ),
        data: (drives) {
          final total = aggregateUsage(drives);
          if (total == null) return const EmptyFolderView();
          final withCapacity =
              drives.where((d) => usedFraction(d) != null).toList();
          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              _TotalCard(usage: total, driveCount: withCapacity.length),
              const SizedBox(height: Spacing.md),
              for (final drive in withCapacity) StorageGauge(drive: drive),
            ],
          );
        },
      ),
    );
  }
}

/// The aggregate "All drives" card: a single gauge bar over the summed
/// capacity, with a "<free> free of <total> · N drive(s)" caption.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.usage, required this.driveCount});

  final ({int totalBytes, int freeBytes, double usedFraction}) usage;
  final int driveCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final drivesLabel = driveCount == 1 ? '1 drive' : '$driveCount drives';

    return Card(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: Radii.cardR),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('All drives', style: textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            ClipRRect(
              borderRadius: Radii.stadiumR,
              child: LinearProgressIndicator(
                value: usage.usedFraction,
                minHeight: 10,
                backgroundColor: scheme.tertiaryContainer,
                valueColor: AlwaysStoppedAnimation(scheme.tertiary),
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              '${formatSize(usage.freeBytes)} free of '
              '${formatSize(usage.totalBytes)} · $drivesLabel',
              style: textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/storage_insights_screen_test.dart`
Expected: PASS — all three widget tests green.

Note: if `Host`'s required constructor params differ from `(id, label, address)`, adjust the `_host` const in the test to match the model — check `app/lib/core/models/host.dart`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/hosts/storage_insights_screen.dart app/test/storage_insights_screen_test.dart
git commit -m "feat(app): storage insights screen (aggregate total + per-drive gauges)"
```

---

### Task 3: Wire the host-card ⋯ menu entry

**Files:**
- Modify: `app/lib/features/hosts/widgets/host_card.dart` (import, `_openStorage`, `_QuickActions` field + menu item + wiring)

- [ ] **Step 1: Add the import**

Near the other feature imports at the top of `app/lib/features/hosts/widgets/host_card.dart`, add:

```dart
import '../storage_insights_screen.dart';
```

- [ ] **Step 2: Add the `_openStorage` navigation helper**

In `_HostCardState`, immediately after the existing `_openSettings` method (around line 186), add:

```dart
  void _openStorage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StorageInsightsScreen(host: widget.host),
      ),
    );
  }
```

- [ ] **Step 3: Pass `onStorage` into `_QuickActions`**

In the `_QuickActions(...)` constructor call (around line 255), add the `onStorage` argument after `onSearch`:

```dart
                  _QuickActions(
                    online: online,
                    onBrowse: () => _openExplorer(context),
                    onSearch: () => _openSearch(context),
                    onStorage: () => _openStorage(context),
                    onTransfers: () => _openTransfers(context),
                    onSettings: () => _openSettings(context),
                    onForget: () => _confirmRemove(context),
                  ),
```

- [ ] **Step 4: Add the field to `_QuickActions`**

In `class _QuickActions`, add the parameter to the constructor and the field. The constructor becomes:

```dart
  const _QuickActions({
    required this.online,
    required this.onBrowse,
    required this.onSearch,
    required this.onStorage,
    required this.onTransfers,
    required this.onSettings,
    required this.onForget,
  });

  final bool online;
  final VoidCallback onBrowse;
  final VoidCallback onSearch;
  final VoidCallback onStorage;
  final VoidCallback onTransfers;
  final VoidCallback onSettings;
  final VoidCallback onForget;
```

- [ ] **Step 5: Handle the menu selection + add the item**

In the `PopupMenuButton<String>` (around line 570), add a `'storage'` case to `onSelected` and an online-only item to `itemBuilder`. The `onSelected` switch becomes:

```dart
          onSelected: (v) {
            switch (v) {
              case 'storage':
                onStorage();
              case 'transfers':
                onTransfers();
              case 'settings':
                onSettings();
              case 'forget':
                onForget();
            }
          },
```

and `itemBuilder` becomes:

```dart
          itemBuilder: (_) => [
            if (online)
              const PopupMenuItem(value: 'storage', child: Text('Storage')),
            const PopupMenuItem(value: 'transfers', child: Text('Transfers')),
            const PopupMenuItem(value: 'settings', child: Text('Settings')),
            const PopupMenuItem(
              value: 'forget',
              child: Text('Forget this computer'),
            ),
          ],
```

- [ ] **Step 6: Analyze and run the existing host-card tests**

Run: `flutter analyze lib/features/hosts && flutter test test/host_card_test.dart`
Expected: analyze reports no issues; existing host-card tests PASS (the new `onStorage` is a required field — if `host_card_test.dart` constructs `_QuickActions` directly it cannot, since it's private, so only the analyzer needs satisfying here).

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/hosts/widgets/host_card.dart
git commit -m "feat(app): add Storage entry to the host card menu (online only)"
```

---

### Task 4: Full verification + sync the second brain

**Files:**
- Modify: `~/Documents/Obsidian Vault/Claude/projects/remote-file-explorer.md` + `log.md`

- [ ] **Step 1: Run the full app suite + analyze**

Run: `flutter analyze && flutter test`
Expected: "No issues found!" and all tests PASS (including the new `aggregateUsage`, screen, and untouched suites).

- [ ] **Step 2: Update the Obsidian project note**

In `~/Documents/Obsidian Vault/Claude/projects/remote-file-explorer.md`: bump `updated:`, change the Active-wave section to mark Storage Insights implemented (screen + helper + menu wiring landed on `feat/storage-insights`, tests green), and add a `## Provenance` line dated today. Append a matching `- YYYY-MM-DD — UPDATE — projects/remote-file-explorer.md — Storage Insights implemented (...)` line to `log.md` (newest first).

- [ ] **Step 3: Report status**

Summarize to the owner: what shipped on the branch, test results, and that the wave is ready for review/merge (and that no agent redeploy is needed, since this is client-only).

---

## Notes for the worker

- All `flutter` commands run from `~/Storage/Projects/remote-file-explorer/app`.
- Lefthook runs format/analyze/test on commit/push — keep commits clean so hooks pass.
- This wave is **client-only**: no agent rebuild, no OpenAPI change, no `v*` tag required until the owner decides to batch a release.
- JDK only matters for a full Android build (`flutter build apk`), not for `flutter test`; if a build is attempted, use `JAVA_HOME=~/.jdks/jbr-21.0.10`.
