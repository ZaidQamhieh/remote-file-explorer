# Feature Roadmap — Remote File Explorer

**Status: PLANNED, NOT STARTED.** Written 2026-06-12. Companion to
`docs/ui-redesign-plan.md` (UI waves A–F) and `docs/ui-design-spec.md`
(Expressive M3 visuals). Features here are sequenced *around* the UI waves —
suggested interleaving at the bottom.

Effort: S (≤1 agent dispatch) · M (2–3) · L (multi-session) · XL (its own plan
doc). Impact: ★ to ★★★ for a personal phone↔PC tool over Tailscale.

---

## Next up (owner-requested): File visibility — hide file types

**Effort S–M · Impact ★★★ · client-side, no agent change needed for v1**

Hide chosen file types / hidden files from listings instead of wading through
junk (`.tmp`, `desktop.ini`, dotfiles, `node_modules`…).

### Behavior
- **Global visibility settings** (SharedPreferences, apply to all hosts):
  - `hideDotfiles` (names starting with `.`) — **default ON**, like every
    mainstream file manager. Dot-*folders* count too.
  - `hiddenExtensions`: user-managed set, no dot, case-insensitive
    (e.g. `tmp, log, bak, ini`).
  - **Presets** as one-tap chips that add to the set:
    "System junk" (`DS_Store`-style: tmp, bak, swp, lock, ini + exact names
    `.DS_Store`, `Thumbs.db`, `desktop.ini`), "Logs" (log, old), plus the
    existing search categories (hide all Archives / Audio / …) reusing the
    category→extension table already mirrored client-side.
  - `hiddenNames`: exact-name matches for the preset entries above.
- **Where the filter applies:**
  - Explorer listings: filter in the `ExplorerState` entries pipeline
    **before** the memoized sort (pure function → trivially unit-testable).
    Pagination note: filter is per-page client-side; a folder of 200 junk
    files may show empty with "200 hidden" — acceptable, the footer explains.
  - Search: filtered by default; the search filters sheet gets an
    "Include hidden items" switch (off by default).
  - Destination picker: dotfolder rule applies, extension rules don't
    (it only shows folders anyway).
  - Favorites pins: never filtered (explicit user intent).
- **Reveal affordances (critical — never make files silently unreachable):**
  - Listing footer when anything is filtered: `12 hidden · Show` — tapping
    reveals for the current session (per-screen, not persisted), with hidden
    items rendered at 55% opacity so they're visibly "hidden".
  - View-options popover: `Show hidden items` eye toggle (same session
    override). Show count badge when >0 are hidden.
- **Settings UI:** Settings → "File visibility" section (tonal card per the
  design spec): dotfiles switch, preset chips, custom-extension input that
  renders entered extensions as deletable chips.

### v2 (needs agent work, do later)
- `Entry.hidden` bool from the agent: Windows `FILE_ATTRIBUTE_HIDDEN`, plus
  dotfile detection server-side — lets Windows-hidden files obey the rule and
  removes name-heuristics from the client. Additive field → backward
  compatible; bump agent minor version.

### Tests
Pure filter function (dotfiles, extensions, exact names, case, folders),
session-reveal state, settings persistence, search include-hidden param.

---

## Tier 1 — near-term (high impact, modest effort)

| # | Feature | Effort | Impact | Notes |
|---|---|---|---|---|
| 1 | **Share-to-app upload ("Send to PC")** | M | ★★★ | Android share-target: share any file from any app → pick host + folder (reuse destination picker) → queued upload. The single biggest daily-convenience win. `receive_sharing_intent` package; ties into the existing transfer queue. |
| 2 | **Zip / unzip on the agent** | M | ★★★ | `POST /v1/fs/compress` (paths→zip) and `/v1/fs/extract` (zip/tar.gz→folder), jailed, async with progress polling (reuse transfer-session pattern). UI: selection-bar "Compress", meta-sheet "Extract here". Server-side Go stdlib only. |
| 3 | **Storage insights** | M | ★★ | Agent endpoint `GET /v1/fs/usage?path=` (du-style aggregated child sizes, time-budgeted like search). UI: "what's eating space" bar list per folder, entry from the dashboard gauge. Pairs with sort-by-size for folders. |
| 4 | **Trash (honest return of `permanent:false`)** | M | ★★ | Agent: move-to-trash on Linux (XDG ~/.local/share/Trash with .trashinfo) and Windows (Recycle Bin via shell API or a `.rfe-trash` fallback dir); `DELETE /v1/fs?permanent=` becomes real; Trash browser screen + restore. We removed the fake flag in June — bring it back implemented, never fake. |
| 5 | **Recents view** | S | ★★ | Agent `GET /v1/fs/recent?limit=` (walk, sort by mtime, time-budgeted — share plumbing with search). UI: "Recent" chip/tab on the dashboard or explorer root. |
| 6 | **Video/audio streaming previews** | S–M | ★★ | `/v1/content` already supports Range; switch video preview from download-temp-file to streaming with seek. Audio: mini-player bar with background-safe lifecycle. |
| 7 | **Biometric app lock** | S | ★ | `local_auth`, optional toggle, lock on cold start + after N minutes background. Cheap privacy win since tokens unlock full PC read/write. |
| 8 | **Per-device read-only mode** | S | ★★ | Agent: `readOnly` flag per device row, enforced in middleware (global read-only already exists — make it per-token); toggle in the app's Devices screen. Lets you pair a "view-only" device safely. |

## Tier 2 — mid-term (bigger lifts)

| # | Feature | Effort | Impact | Notes |
|---|---|---|---|---|
| 9 | **Background transfers + notifications** | L | ★★★ | Android foreground service so uploads/downloads survive app switch; progress notification with pause/cancel actions; completion notifications. Already on the engineering backlog — the transfer engine was rebuilt to be resumable, this is the payoff. Do before/with photo backup. |
| 10 | **Live events channel** | L | ★★ | `GET /v1/events` SSE (simpler than WS through proxies): fs-change events (fsnotify on open listings), transfer progress push. Kills pull-to-refresh. Spec it properly in the OpenAPI first — contract-first this time. |
| 11 | **Camera-roll backup (photo sync)** | XL | ★★★ | Phone→PC one-way sync of DCIM: hash-based dedupe (agent already hashes), date-folder layout, Wi-Fi-only + charging rules, runs on the background-transfer service (#9 is a hard prerequisite). This turns the app into a personal Google-Photos-backup replacement — biggest strategic feature in the doc. |
| 12 | **mDNS discovery** | M | ★ | `internal/discovery/` placeholder exists. Agent broadcasts `_rfe._tcp`; pairing screen lists discovered agents (LAN only; Tailscale users rarely need it — hence ★). |
| 13 | **Available-offline pins** | L | ★★ | Mark folders "keep offline": pinned listings + file bodies cached locally, refreshed opportunistically (or by #10 events). Read-only offline access. |

## Horizon / ambitious

- **PC↔PC copy** (agent-to-agent transfer brokered by the phone): both agents
  are already HTTP servers with the same chunk protocol — the phone could
  instruct host A to pull from host B. Genuinely novel for this app class. (L)
- **Home-screen widget / Quick Settings tile**: storage-at-a-glance + active
  transfer progress. (M, after #9 so there's something live to show)
- **App shortcuts** (long-press icon → Search / Transfers / last host). (S)
- **Real audit log**: per-device action log on the agent (the docs once falsely
  claimed one existed — make it true), viewable in Devices UI. (M)
- **Dual-pane / tabs**: two explorer panes with drag-between (tablet two-pane
  from UI Wave F is the stepping stone). (L)

## Explicit non-goals

Remote shell/command execution (security scope creep on a file tool), Chromecast,
iOS port, content/full-text search indexing, sync conflict resolution
(two-way sync) — one-way backup only.

## Additional UI/UX ideas (beyond the redesign waves)

- **Long-press preview peek**: long-press an image/video tile → quick floating
  preview (release to dismiss), no navigation.
- **Type-ahead jump**: in large folders, typing with keyboard (or a small
  jump-to field) scrolls to first match — pairs with compact density.
- **Transfer ETA in the explorer mini-bar** ("2 files · 0:42 left").
- **Path copy/paste interop**: paste a `/home/...` or `C:\...` path into the
  breadcrumb overflow menu to jump directly.
- **Per-host accent**: derive each host card's accent from its name hash so
  multiple PCs are visually distinct (within the design spec's one-accent rule).
- **Haptic patterns**: distinct success/failure haptics on transfer completion
  (feedback.dart already centralizes this).
- **Smart empty folders**: empty folder state offers "Upload here" + "New
  folder" actions inline instead of a bare message.

## Suggested sequencing (interleaved with UI waves)

1. UI Waves A–C (redesign plan) — foundations + the screens everything else
   hangs off.
2. **File visibility** (this doc's headline) — small, self-contained, lands
   right after Wave C since it lives in the explorer pipeline + settings.
3. Tier 1 #1 share-to-app, #2 zip/unzip, #6 streaming preview — alongside UI
   Waves D–E (disjoint code).
4. UI Wave F, then Tier 1 remainder (#3 insights, #4 trash, #5 recents,
   #7 lock, #8 per-device RO).
5. Tier 2: #9 background transfers → #11 photo backup (in that order),
   #10 events when polling starts to hurt.
6. Re-evaluate horizon items once the above ships.

Every agent-side feature: contract goes into `protocol/openapi.yaml` in the
same commit as the implementation — the spec drifted once already; don't repeat it.
