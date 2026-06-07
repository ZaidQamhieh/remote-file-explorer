# Wave 3 Pillar C — UX Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the explorer feel like a daily-driver file manager — instant offline-capable navigation, friendly empty/error/offline states, drag-and-drop move, and a refined batch-ops experience.

**Architecture:** A file-backed `ListingCache` (one JSON file per host) lets `ExplorerNotifier` paint cached entries instantly and stay browsable when the PC is unreachable, flagging staleness. Shared state widgets replace bare spinners/errors. Drag-and-drop wraps existing tiles in `LongPressDraggable`/`DragTarget` to move into folders. Batch ops gain select-all, a count badge, and per-operation progress. Dart-only; no agent changes.

**Tech Stack:** Flutter/Dart, Riverpod **2.6.1** (do not bump), `path_provider`, existing `AgentClient`.

**Spec:** `docs/superpowers/specs/2026-06-07-wave3-settings-updater-polish-design.md` (Pillar C).

**Environment:** `export PATH="$HOME/flutter/bin:$PATH"`; run from `app/`.

**Coordinates with Pillars A/B:** touches `explorer_screen.dart`; no overlap with the Go work. Minor merge possible with B's `host_list_screen.dart` banner — integrate as in Wave 2.

---

## File Structure

- Create: `app/lib/core/storage/listing_cache.dart` — per-host on-disk listing cache
- Create: `app/test/listing_cache_test.dart`
- Modify: `app/lib/features/explorer/explorer_state.dart` — `stale`/`fromCache`/`offline` flags; cache-aware `_load`
- Create: `app/lib/core/ui/state_views.dart` — `EmptyFolderView`, `ErrorRetryCard`, `OfflineBanner`, `ListingSkeleton`
- Create: `app/test/state_views_test.dart`
- Modify: `app/lib/features/explorer/explorer_screen.dart` — wire state views, drag-and-drop, batch refinements

---

## Task 1: `ListingCache` — file-backed per-host cache

**Files:**
- Create: `app/lib/core/storage/listing_cache.dart`
- Test: `app/test/listing_cache_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/storage/listing_cache.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('rfe_cache_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Entry mkEntry(String name) => Entry(
        name: name,
        path: '/root/$name',
        isDir: false,
        size: 1,
        mimeType: 'text/plain',
        mode: '-rw-r--r--',
        modified: DateTime(2026, 1, 1),
        created: DateTime(2026, 1, 1),
        isSymlink: false,
      );

  test('put then get round-trips entries', () async {
    final cache = ListingCache(baseDir: tmp);
    await cache.put('host-1', '/root', [mkEntry('a.txt'), mkEntry('b.txt')]);

    final got = await cache.get('host-1', '/root');
    expect(got, isNotNull);
    expect(got!.entries.map((e) => e.name), ['a.txt', 'b.txt']);
    expect(got.fetchedAt.isBefore(DateTime.now().add(const Duration(seconds: 1))), isTrue);
  });

  test('get returns null for unknown path', () async {
    final cache = ListingCache(baseDir: tmp);
    expect(await cache.get('host-1', '/nope'), isNull);
  });

  test('evicts oldest beyond capacity', () async {
    final cache = ListingCache(baseDir: tmp, maxEntries: 2);
    await cache.put('h', '/p1', [mkEntry('1')]);
    await Future.delayed(const Duration(milliseconds: 5));
    await cache.put('h', '/p2', [mkEntry('2')]);
    await Future.delayed(const Duration(milliseconds: 5));
    await cache.put('h', '/p3', [mkEntry('3')]); // evicts /p1

    expect(await cache.get('h', '/p1'), isNull);
    expect(await cache.get('h', '/p2'), isNotNull);
    expect(await cache.get('h', '/p3'), isNotNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter test test/listing_cache_test.dart`
Expected: FAIL — `listing_cache.dart` not found.

- [ ] **Step 3: Implement** — `listing_cache.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/entry.dart';

/// A cached directory listing plus the time it was fetched.
class CachedListing {
  CachedListing({required this.entries, required this.fetchedAt});
  final List<Entry> entries;
  final DateTime fetchedAt;
}

/// Persists recent directory listings per host so navigation is instant and the
/// explorer stays browsable (read-only) while the host is unreachable.
///
/// Storage: one JSON file per host under the app documents dir, mapping
/// `path -> { fetchedAt, entries }`. Capped at [maxEntries] directories per
/// host (oldest `fetchedAt` evicted first).
class ListingCache {
  ListingCache({this.baseDir, this.maxEntries = 200});

  /// Override for tests; defaults to the app documents dir.
  final Directory? baseDir;
  final int maxEntries;

  Future<Directory> _dir() async {
    final base = baseDir ?? await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/listing_cache');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _fileFor(String hostId) async {
    final safe = hostId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${(await _dir()).path}/$safe.json');
  }

  Future<Map<String, dynamic>> _read(String hostId) async {
    final f = await _fileFor(hostId);
    if (!await f.exists()) return {};
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(String hostId, Map<String, dynamic> data) async {
    final f = await _fileFor(hostId);
    await f.writeAsString(jsonEncode(data));
  }

  Future<void> put(String hostId, String path, List<Entry> entries) async {
    final data = await _read(hostId);
    data[path] = {
      'fetchedAt': DateTime.now().toIso8601String(),
      'entries': entries.map((e) => e.toJson()).toList(),
    };

    // Evict oldest beyond capacity.
    if (data.length > maxEntries) {
      final keys = data.keys.toList()
        ..sort((a, b) {
          final fa = DateTime.tryParse(
                  (data[a] as Map)['fetchedAt'] as String? ?? '') ??
              DateTime(0);
          final fb = DateTime.tryParse(
                  (data[b] as Map)['fetchedAt'] as String? ?? '') ??
              DateTime(0);
          return fa.compareTo(fb);
        });
      for (final k in keys.take(data.length - maxEntries)) {
        data.remove(k);
      }
    }
    await _write(hostId, data);
  }

  Future<CachedListing?> get(String hostId, String path) async {
    final data = await _read(hostId);
    final raw = data[path];
    if (raw is! Map) return null;
    final fetchedAt =
        DateTime.tryParse(raw['fetchedAt'] as String? ?? '') ?? DateTime(0);
    final entries = ((raw['entries'] as List?) ?? const [])
        .map((e) => Entry.fromJson(e as Map<String, dynamic>))
        .toList();
    return CachedListing(entries: entries, fetchedAt: fetchedAt);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter test test/listing_cache_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/storage/listing_cache.dart app/test/listing_cache_test.dart
git commit -m "feat(app): file-backed per-host ListingCache (tested)"
```

---

## Task 2: Cache-aware explorer load with stale/offline flags

**Files:**
- Modify: `app/lib/features/explorer/explorer_state.dart` (ExplorerState fields + copyWith + ExplorerNotifier `_load`)

- [ ] **Step 1: Add flags to `ExplorerState`**

In `explorer_state.dart`, add three booleans to `ExplorerState` (constructor, fields, and `copyWith`):

Constructor params (add with defaults):
```dart
    this.stale = false,
    this.offline = false,
```
Fields:
```dart
  final bool stale;   // showing cached data, refresh in progress or failed
  final bool offline; // last live fetch failed; data is from cache only
```
`copyWith` params + passthrough:
```dart
    bool? stale,
    bool? offline,
```
```dart
        stale: stale ?? this.stale,
        offline: offline ?? this.offline,
```

- [ ] **Step 2: Make `_load` cache-aware**

Add a `ListingCache` field to `ExplorerNotifier` and rewrite `_load`. Replace the existing `_load` (lines ~117-125) with:

```dart
  final ListingCache _cache = ListingCache();

  Future<void> _load() async {
    final path = state.currentPath;

    // 1. Paint cached entries instantly (if any) while we fetch live.
    final cached = await _cache.get(arg.host.id, path);
    if (cached != null) {
      state = state.copyWith(
        entries: cached.entries,
        loading: false,
        stale: true,
        offline: false,
        error: null,
        selected: {},
      );
    } else {
      state = state.copyWith(loading: true, error: null, selected: {});
    }

    // 2. Fetch live; on success replace + cache; on failure fall back to cache.
    try {
      final listing = await arg.client.list(path);
      await _cache.put(arg.host.id, path, listing.entries);
      state = state.copyWith(
        loading: false,
        entries: listing.entries,
        stale: false,
        offline: false,
        error: null,
      );
    } catch (e) {
      if (cached != null) {
        // Keep cached entries; mark offline rather than erroring out.
        state = state.copyWith(loading: false, stale: true, offline: true);
      } else {
        state = state.copyWith(loading: false, error: e.toString());
      }
    }
  }
```

Add the import at the top of the file:
```dart
import '../../core/storage/listing_cache.dart';
```

- [ ] **Step 3: Analyze + run existing tests**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter analyze lib/features/explorer/explorer_state.dart && flutter test`
Expected: `No issues found!`; existing tests still PASS.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/explorer/explorer_state.dart
git commit -m "feat(app): cache-aware explorer load with stale/offline flags"
```

---

## Task 3: Shared state views

**Files:**
- Create: `app/lib/core/ui/state_views.dart`
- Test: `app/test/state_views_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/ui/state_views.dart';

void main() {
  testWidgets('EmptyFolderView shows message', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: EmptyFolderView()),
    ));
    expect(find.textContaining('empty'), findsOneWidget);
  });

  testWidgets('ErrorRetryCard calls onRetry', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ErrorRetryCard(message: 'boom', onRetry: () => tapped = true),
      ),
    ));
    expect(find.text('boom'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(tapped, isTrue);
  });

  testWidgets('OfflineBanner shows offline text', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: OfflineBanner()),
    ));
    expect(find.textContaining('Offline'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter test test/state_views_test.dart`
Expected: FAIL — `state_views.dart` not found.

- [ ] **Step 3: Implement** — `state_views.dart`:

```dart
import 'package:flutter/material.dart';

/// Friendly empty-directory placeholder.
class EmptyFolderView extends StatelessWidget {
  const EmptyFolderView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 64, color: c.outline),
          const SizedBox(height: 12),
          Text('This folder is empty',
              style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

/// Error card with a retry action.
class ErrorRetryCard extends StatelessWidget {
  const ErrorRetryCard({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: c.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin banner shown when the explorer is displaying cached data while offline.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: c.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 16, color: c.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Offline — showing cached files',
                  style: TextStyle(color: c.onTertiaryContainer, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmer-free lightweight skeleton list shown during first load.
class ListingSkeleton extends StatelessWidget {
  const ListingSkeleton({super.key, this.rows = 8});
  final int rows;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    Widget bar(double w) => Container(
          height: 12,
          width: w,
          decoration: BoxDecoration(
            color: c.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return ListView.builder(
      itemCount: rows,
      itemBuilder: (_, __) => ListTile(
        leading: CircleAvatar(backgroundColor: c.surfaceContainerHighest),
        title: bar(160),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: bar(90),
        ),
      ),
    );
  }
}
```

(Note: `surfaceContainerHighest` exists in the Material 3 color scheme on the pinned Flutter; if the analyzer flags it, use `c.surfaceVariant`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter test test/state_views_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/ui/state_views.dart app/test/state_views_test.dart
git commit -m "feat(app): shared empty/error/offline/skeleton state views (tested)"
```

---

## Task 4: Wire state views into the explorer body

**Files:**
- Modify: `app/lib/features/explorer/explorer_screen.dart`

- [ ] **Step 1: Replace the body builder**

Find where the explorer builds its body from `state` (the `state.loading` spinner / `state.error` / entries list — around `_buildBody` or inline in `build`, near line 65-100). Add the import:
```dart
import '../../core/ui/state_views.dart';
```
Replace the loading/error/empty branches so that:
- first load (`state.loading && state.entries.isEmpty`) → `const ListingSkeleton()`
- hard error with no cache (`state.error != null && state.entries.isEmpty`) →
  `ErrorRetryCard(message: state.error!, onRetry: notifier.refresh)`
- empty dir (`!state.loading && state.entries.isEmpty && state.error == null`) →
  `const EmptyFolderView()`
- otherwise the list/grid as today, with an `OfflineBanner()` shown above it when
  `state.offline` is true.

Concretely, wrap the existing list/grid in a `Column`:
```dart
Column(
  children: [
    if (state.offline) const OfflineBanner(),
    Expanded(child: /* existing list or grid widget */),
  ],
)
```
and guard the three placeholder branches before it as described.

- [ ] **Step 2: Analyze + build**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter analyze lib/ && flutter build apk --debug`
Expected: `No issues found!`; APK builds.

- [ ] **Step 3: Manual verification**

- Open a folder, then stop the agent (`systemctl --user stop rfe-agent`), re-enter the
  folder → cached entries with the **Offline** banner; a write attempt shows an error,
  no crash. Restart the agent → banner clears on refresh.
- Open an empty folder → friendly empty view. Force an error on a never-visited folder
  (e.g. revoke token) → error card with a working Retry.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/explorer/explorer_screen.dart
git commit -m "feat(app): explorer uses skeleton/empty/error/offline state views"
```

---

## Task 5: Drag-and-drop move

**Files:**
- Modify: `app/lib/features/explorer/explorer_screen.dart`

This is interaction UI; verified manually on a device.

- [ ] **Step 1: Make folder tiles drop targets and all tiles draggable**

In `_EntryListTile` (and `_EntryGridCell`), wrap the row content so that:
- Every entry is a `LongPressDraggable<Entry>` with `data: entry`, a `feedback` of a
  small `Material` chip showing the entry name + icon, and `childWhenDragging` dimmed.
- Folder entries additionally wrap their child in a `DragTarget<Entry>` whose
  `onWillAcceptWithDetails` returns `true` only when the dragged entry's path differs
  from the folder, and `onAcceptWithDetails` performs the move.

Because the tiles are currently `StatelessWidget`s that receive callbacks, add an
`onMoveInto` callback parameter: `final Future<void> Function(Entry dragged, String destFolder)? onMoveInto;` and pass it from the list builder. The builder implements it as:

```dart
Future<void> _moveInto(Entry dragged, String destFolder) async {
  try {
    await client.move([dragged.path], destFolder);
    await ref.read(explorerProvider(_arg).notifier).refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Moved ${dragged.name}')),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Move failed: $e')),
      );
    }
  }
}
```

Example wrapping for a folder cell child (`entry.isDir`):
```dart
Widget tile = /* existing ListTile/cell */;
if (multiSelect) {
  // selection mode: keep tap-to-toggle, skip drag to avoid gesture conflict
  return tile;
}
tile = LongPressDraggable<Entry>(
  data: entry,
  feedback: Material(
    elevation: 4,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.drag_indicator), const SizedBox(width: 4), Text(entry.name),
      ]),
    ),
  ),
  childWhenDragging: Opacity(opacity: 0.4, child: tile),
  child: tile,
);
if (entry.isDir) {
  tile = DragTarget<Entry>(
    onWillAcceptWithDetails: (d) => d.data.path != entry.path,
    onAcceptWithDetails: (d) => onMoveInto?.call(d.data, entry.path),
    builder: (ctx, cand, rej) => Container(
      decoration: cand.isNotEmpty
          ? BoxDecoration(
              color: Theme.of(ctx).colorScheme.primaryContainer.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: tile,
    ),
  );
}
return tile;
```

- [ ] **Step 2: Breadcrumb drop targets (move "up")**

In `_BreadcrumbBar`, wrap each crumb in a `DragTarget<Entry>` that moves the dragged
entry into that ancestor path (same `onMoveInto` plumbed down). Highlight on hover.

- [ ] **Step 3: Analyze + build**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter analyze lib/ && flutter build apk --debug`
Expected: `No issues found!`; APK builds.

- [ ] **Step 4: Manual verification (device)**

- Long-press a file and drag it onto a folder → it moves (confirm on the PC filesystem
  and that the folder now contains it after refresh).
- Drag onto a breadcrumb crumb → moves into that ancestor.
- Dragging a folder onto itself is rejected (no-op).
- In multi-select mode, dragging is disabled (selection still works).

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/explorer/explorer_screen.dart
git commit -m "feat(app): drag-and-drop move onto folders and breadcrumbs"
```

---

## Task 6: Batch-ops refinement

**Files:**
- Modify: `app/lib/features/explorer/explorer_screen.dart` (`_MultiSelectBar` + app bar)

`selectAll()`, `clearSelection()`, and the batch methods already exist on the notifier.

- [ ] **Step 1: Select-all + count badge in the multi-select app bar**

When `state.multiSelect` is true, show a top app bar (or augment the bottom bar) with:
- a count badge: `Text('${state.selected.length} / ${state.entries.length}')`
- a **select-all / clear toggle**: if all entries selected → "Clear" (calls
  `notifier.clearSelection`), else "Select all" (calls `notifier.selectAll`).

Add to `_MultiSelectBar.build`, replacing the bare `Text('${state.selected.length} selected')` with:
```dart
            TextButton.icon(
              onPressed: state.selected.length == state.entries.length
                  ? notifier.clearSelection
                  : notifier.selectAll,
              icon: Icon(state.selected.length == state.entries.length
                  ? Icons.deselect
                  : Icons.select_all),
              label: Text('${state.selected.length}/${state.entries.length}'),
            ),
```

- [ ] **Step 2: Batch progress + per-item error summary**

The current `moveSelected`/`copySelected`/`deleteSelected` call batch endpoints that
already return per-item results (the agent's `BatchResult` array). Surface failures: in
`_showDestPicker` and `_confirmDelete`, after the call, if the operation reported any
failed items, show a summary dialog listing them instead of a generic success toast.

Add a helper to `ExplorerNotifier` that returns the batch results so the UI can inspect
them. Modify `moveSelected`/`copySelected`/`deleteSelected` to return the raw response
map (they currently return `Future<void>`):

```dart
  Future<Map<String, dynamic>> moveSelected(String destDir) async {
    final res = await arg.client.move(state.selected.toList(), destDir);
    await _load();
    return res;
  }
```
(do the same for `copySelected` → `arg.client.copy(...)`, and `deleteSelected` →
`arg.client.delete(...)`; all three client methods already return
`Future<Map<String, dynamic>>`.)

Then in `_MultiSelectBar`, inspect the returned map's `results` array for entries whose
`ok == false` and, if any, show:
```dart
Future<void> _reportBatch(BuildContext context, Map<String, dynamic> res,
    String successVerb) async {
  final results = (res['results'] as List?) ?? const [];
  final failed = results
      .whereType<Map>()
      .where((r) => r['ok'] == false)
      .toList();
  if (!context.mounted) return;
  if (failed.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$successVerb successfully')));
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('$successVerb with ${failed.length} error(s)'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: failed.map((f) {
            final err = f['error'];
            final msg = err is Map ? (err['message'] ?? err['code'] ?? 'failed')
                                   : 'failed';
            return ListTile(
              dense: true,
              title: Text('${f['path'] ?? '?'}'),
              subtitle: Text('$msg'),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}
```
Wire `_showDestPicker`/`_confirmDelete` to call `_reportBatch(context, res, 'Moved'/'Copied'/'Deleted')` with the returned map. (Verified against `agent/internal/fsops` `BatchResult` — JSON shape is `{"path": string, "ok": bool, "error": {"code","message"}}`, wrapped as `{"results": [...]}`.)

- [ ] **Step 3: Analyze + build**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter analyze lib/ && flutter build apk --debug`
Expected: `No issues found!`; APK builds.

- [ ] **Step 4: Manual verification**

- Enter multi-select, tap select-all → all items selected, badge shows `N/N`; tap again
  → cleared.
- Select several items, delete → success toast; make one fail (e.g. a read-only sub-path
  or a file removed underneath) → summary dialog lists the failed item, the rest still
  succeed.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/explorer/explorer_screen.dart app/lib/features/explorer/explorer_state.dart
git commit -m "feat(app): batch ops select-all, count badge, per-item error summary"
```

---

## Pillar C Verification (run after all tasks)

- [ ] `cd app && flutter test` — all unit/widget tests green (models, listing cache, state views).
- [ ] `flutter analyze lib/` → `No issues found!`; `flutter build apk --debug` succeeds.
- [ ] Offline: browse a folder, stop the agent, re-enter → cached entries + Offline banner;
      restart → refreshes clean.
- [ ] States: empty folder view; error card with working Retry; skeleton on first load.
- [ ] Drag a file onto a folder and onto a breadcrumb → moves (verified on PC).
- [ ] Batch: select-all + count badge; batch delete with one failure → error summary,
      others succeed.
```

> **Riverpod guard:** after `flutter pub get` at any point, confirm the resolved
> `flutter_riverpod` line still reads `2.6.1`. If anything pulled 3.x, pin it back in
> `pubspec.yaml` before continuing.
