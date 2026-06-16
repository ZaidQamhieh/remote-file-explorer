# Storage Insights — design

_2026-06-16. Wave: P0 #3 "Storage insights", reduced to **drive-summary-only, client-side**.
Recents (#5) was dropped at the owner's request. No agent / OpenAPI / agent-redeploy work._

## Goal

Give a single, discoverable place to see a host's storage at a glance: an
across-all-drives **aggregate total** plus a per-drive gauge list. Today this
information exists only scattered across the **host card** gauges
(`host_card.dart`) and **per-host Settings → About** rows (`settings_screen.dart`),
with no aggregate and no dedicated entry point.

## Non-goals

- No per-folder / recursive "where did my space go" analysis (that was the rejected
  `GET /fs/usage` walk variant).
- No new agent endpoint. We reuse the existing `GET /system/drives` via the
  client's `drives()` and `drivesProvider`.
- No changes to the existing host-card gauges or the About drive rows.

## Architecture

Pure client (Flutter / Riverpod). Reuses:

- `drivesProvider` — `FutureProvider.autoDispose.family<List<Drive>, String>`
  (currently in `app/lib/features/explorer/drives_view.dart:26`).
- `StorageGauge` widget + `usedFraction` helper
  (`app/lib/features/hosts/widgets/storage_gauge.dart`).
- `state_views` — `ListingSkeleton`, `ErrorRetryCard`, `EmptyFolderView`.
- `format.formatSize`.

## Components

### 1. `aggregateUsage(List<Drive>)` — pure helper

New function alongside `usedFraction` in `storage_gauge.dart`.

- Considers only drives with real capacity: `totalBytes != null && totalBytes > 0
  && freeBytes != null`.
- Sums `totalBytes` and `freeBytes` across those drives.
- Returns a small result `({int totalBytes, int freeBytes, double usedFraction})`
  or `null` when **no** drive has capacity.
- `usedFraction = ((sumTotal - sumFree) / sumTotal).clamp(0, 1)`, matching the
  single-drive contract.

Kept pure and dependency-free so it is unit-testable in isolation.

### 2. `StorageInsightsScreen`

New file `app/lib/features/hosts/storage_insights_screen.dart`. `ConsumerWidget`
taking a `Host`. Watches `drivesProvider(host.id)`:

- **loading** → `ListingSkeleton`.
- **error** → `ErrorRetryCard(message: 'Could not load storage: $e', onRetry:
  invalidate(drivesProvider(host.id)))`.
- **data, no drive has capacity** → `EmptyFolderView` (or an equivalent "No
  storage info" message).
- **data** → scrollable `Column`:
  - **Total card** (top): a single gauge bar built from `aggregateUsage`, with a
    `'<free> free of <total>'` label and a `'<n> drives'` subtitle. Visually
    consistent with `StorageGauge` (same `LinearProgressIndicator` styling /
    theme tokens).
  - **Per-drive list**: `StorageGauge` for each drive (drives without capacity
    render nothing, per the widget's existing behavior).

`AppBar` title: `'<host.label> · Storage'` (single-line title, ellipsized),
consistent with how `DrivesView` titles with the host label.

### 3. Entry point — host-card overflow menu

In `_QuickActions` (`host_card.dart:570`):

- Add a `VoidCallback onStorage` field (alongside `onTransfers` / `onSettings` /
  `onForget`).
- Add a `'storage'` case to `onSelected`.
- Include a `PopupMenuItem(value: 'storage', child: Text('Storage'))` in
  `itemBuilder` **only when `online`** (drives require the live agent — same
  spirit as Search being online-gated). Place it above `'transfers'`.
- Wire `onStorage` where `_QuickActions` is constructed to push
  `StorageInsightsScreen(host)` via `MaterialPageRoute`.

## Data flow

Host card ⋯ menu → "Storage" → `StorageInsightsScreen(host)` →
`drivesProvider(host.id)` (cached, `autoDispose`, refetched per open) → render.
Refresh by invalidating the provider (retry button; pull-to-refresh optional, not
required for MVP).

## Error handling

Entirely through existing `state_views`; no new error patterns. No-capacity drives
are excluded from the aggregate and skipped by `StorageGauge`.

## Testing

- **Unit** (`aggregateUsage`): empty list → null; all-zero/no-capacity → null;
  mixed (some with, some without capacity) → sums only the valid ones and computes
  the right fraction; single drive → matches `usedFraction`.
- **Widget** (`StorageInsightsScreen`): with a fake `drivesProvider` override —
  data state renders the total card + N gauges; error state renders
  `ErrorRetryCard`; no-capacity state renders the empty view.

## Files touched

- `app/lib/features/hosts/widgets/storage_gauge.dart` — add `aggregateUsage`.
- `app/lib/features/hosts/storage_insights_screen.dart` — new screen.
- `app/lib/features/hosts/widgets/host_card.dart` — `onStorage` + menu item + wiring.
- `test/...` — unit + widget tests mirroring existing patterns.

## Risks / notes

- Importing `drivesProvider` from `drives_view.dart` couples a hosts-feature screen
  to an explorer-feature file. Acceptable for now (YAGNI); if it grates, the
  provider can later move to a shared `core/api` location — out of scope here.
- Aggregate across drives of mixed types (e.g. a USB stick + system disk) is a
  simple byte sum; that is the intended "total space" semantics.
