# NEXT_SESSION — start here

_Handoff written 2026-06-14. Read this, then `CLAUDE.md`._

## State: v1.10.0+18 released OTA

This session shipped, all on master, all CI-green, bundled into **v1.10.0 (build 18)**
(`./release.sh` published `~/.rfe-agent/updates/rfe-1.10.0-18.apk`):
- **fix**: view-options sheet now watches live `explorerProvider` (selected segment/sort
  chip moved the listing but not the UI — it had captured a snapshot). `2c69810`
- **Wave 0 — settings architecture** (`adea946` core + `01437cc` UI): two-tier
  `core/settings/` — `AppDefaults` + sparse per-host `DeviceOverrides`, resolved
  `deviceOverride ?? appDefault`; migration folds legacy `view_prefs` keys in. New **App
  Settings** screen (gear in dashboard) + per-device override card. View-options quick
  controls now set the app default. See memory `project-rfe-wave0-settings`.
- **Wave G1 — in-app text editor** (`b852455`): `PUT /v1/content`, atomic/jailed/mtime-
  optimistic. Edit button in text preview.
- **Wave G3 — write-conflict resolution** (`050bc4d`): Overwrite/Keep-both/Skip on
  copy/move/upload collisions; upload collision now 409 (was 500); `fsops.Copy/Move` gained
  `overwrite`.
- **Wave G4 — duplicate-in-place** (`c9db427`): Duplicate button in the detail sheet.
  See memory `project-rfe-waveG1-text-editor` (covers G1+G3+G4).

G1/G3 built by **parallel Sonnet workers** (agent + client against a frozen contract);
Wave 0 + G4 built inline by Opus.

## ⚠️ DO FIRST: redeploy the agent — it is STALE

The running agent binary `~/.local/bin/rfe-agent` is from **Jun 12 (reports v1.1.0)** and
**predates the G1/G3/G4 agent-side changes**. So on the real PC right now:
- `PUT /v1/content` (text editor save) → 404
- copy/move `overwrite` flag → ignored; duplicate-in-place → hits the OLD same-path no-op
- upload collision → 500 instead of 409

The app (1.10.0) already expects these. **Rebuild + restart the agent:**
```sh
cd ~/Storage/Projects/remote-file-explorer/agent
PATH="$PATH:~/.local/go/bin" go build -o ~/.local/bin/rfe-agent ./cmd/agent
systemctl --user restart rfe-agent
```
(Verify: `curl -sk https://127.0.0.1:8765/v1/health`. Agent LAN 192.168.1.106:8765,
Tailscale 100.126.220.27:8765, cert fp 9247f266…)

## The "update failed: AgentApiException" report — RESOLVED (was transient)

Debugged live: agent + BOTH update endpoints verified working (`/app/latest` → 200 with
correct JSON; `/app/download` → 206 with a valid APK `PK\x03\x04`). Phone token valid,
seen minutes before. **`AgentApiException(0,'UNKNOWN',…)` is the client's catch-all for
ANY failed Dio request** (`_apiError`/`_throwTransferError` wrap connection drops + timeouts,
not just HTTP errors). User says it now works — it was a transient drop on the **77 MB
APK download, which is NOT resumable**, so any network blip fails the whole thing opaquely.

**Candidate hardening (worth a small wave): resumable APK OTA download.** The agent already
serves Range (`http.ServeContent`); make the client `downloadApk` resume from the partial
file + show a real error instead of `UNKNOWN`. Pairs with addendum I3 (connection
diagnostics). Low-ish effort, removes a real annoyance.

## Then pick next (priority)

1. **Redeploy agent (above) — blocking for G1/G3/G4 to actually work on the PC.**
2. **Resumable APK download** (small, fixes the reported pain) — optional but cheap.
3. **Wave H1 — active sessions + remote device revocation** (security; remaining item of the
   addendum "top-3"; agent-led, good parallel-worker split). Note device list + revoke
   already exist (Wave 3); H1 adds last-seen/address/version + productized revoke UI.
4. **Wave G2 — persistent cut/copy/paste clipboard** (client-side, daily value).
5. Loose end: fold **file-visibility** into the Wave 0 two-tier model.

## Token note (owner is cost-sensitive)

Opus orchestration is the expensive part, not the Sonnet workers — workers offload *writing
code*, but Opus still pays to explore the repo, freeze contracts, brief, and review. For
small/coupled tasks, inline is cheaper than dispatching (a cold worker re-reads context and
Opus still briefs+reviews). Reserve parallel workers for genuinely large, disjoint
agent↔client waves. Keep status write-ups short.
