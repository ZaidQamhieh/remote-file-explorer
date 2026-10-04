Requirements:

1. The deliverable must be a desktop "PC control" app for RFE built with Tauri.
   Accept: the owner's answers to open questions 1, 2 and 5 turn "PC control" into a checkable feature list. Until then only requirements 3 to 9 are testable.
   Source: request ("the RFE desktop 'PC control' app (Tauri)").

2. The trial must record, for each read-only agent on this requirements step, whether it beat doing the step inline.
   Accept: one agent run and one inline run exist for this step, with the same metrics recorded for both. Which metrics count is open question 8. The 2026-10-02 trial recorded tokens, seconds, and counts of requirements, open questions and conflicts, and left the inline cost unmeasured (`/home/zaid/Documents/Obsidian Vault v2/notes/agents/decisions/requirements-agent-2026-10-02.md:6-9`).
   Source: request ("measure whether each one beats doing the step inline").

3. The first slice must be a Tauri window that pairs with the local agent and lists devices. The slice is pending the owner's approval.
   Accept: with the agent running on the same machine, opening the window and completing pairing shows a device list that contains the window's own device. Which device list is meant is open question 3.
   Source: request ("Thin first slice the owner will be asked to approve").

4. The window must reach the agent on the same PC over HTTPS, at the agent's address.
   Accept: with `go run ./cmd/agent -addr 127.0.0.1:8765` running, the window connects and `GET /v1/health` succeeds from it. The contract's default server is host 127.0.0.1, port 8765. Address entry or discovery is open question 2.
   Source: request ("pairs with the local agent"); `/home/zaid/Projects/rfe-rn/protocol/openapi.yaml:44-47`; `/home/zaid/Projects/rfe-rn/CLAUDE.md:27`.

5. Whichever enrollment call the window makes (/pair, /pair/request, /login or /register), it must send the device-identity proof. That means fetching a nonce from `POST /auth/challenge`, signing it with a persistent Ed25519 key, and sending devicePublicKey, nonce and signature.
   Accept: an enrollment call without the three fields gets 400 `DEVICE_KEY_REQUIRED`. The window's call succeeds and the agent pins the key to the device row.
   Source: `/home/zaid/Projects/rfe-rn/protocol/openapi.yaml:33-35`; `/home/zaid/Projects/rfe-rn/agent/internal/server/challenge.go:133-135`; `/home/zaid/Projects/rfe-rn/agent/internal/server/pair.go:84`; `/home/zaid/Projects/rfe-rn/agent/internal/server/pair_request.go:79`; `/home/zaid/Projects/rfe-rn/agent/internal/server/login.go:70`.

6. The window must verify the agent's certificate fingerprint before it sends a pairing code, password or token. It must refuse a later certificate mismatch.
   Accept: against a test agent with a different certificate after pairing, the window refuses the connection and sends no credential. Whether Tauri can do fingerprint pinning is unconfirmed (Risks).
   Source: `/home/zaid/Documents/Obsidian Vault v2/notes/rfe/references/architecture-review.md:22` ("send no credentials before verification"); `/home/zaid/Projects/rfe-rn/CLAUDE.md:89-92` (the trust model the phone follows). Whether this trust model binds the desktop app is an inference (see Assumed).

7. The window must request the device list with `GET /v1/devices`.
   Accept: with an admin (login/register) session the list includes other devices with lastAddress and lastVersion. With a /pair-minted or approve-on-PC token it shows a one-element array holding only id, label, created, lastSeen and current.
   Source: request (slice); `/home/zaid/Projects/rfe-rn/protocol/openapi.yaml:1589-1598`; `/home/zaid/Projects/rfe-rn/agent/internal/server/settings_handlers.go:272-293`.

8. The window must handle the non-admin shape of `GET /devices` and 403 FORBIDDEN from admin-gated calls without crashing.
   Accept: with a /pair token, the window renders the list and calls to `/pairing/generate`, `/pair/requests` and `/metrics` show an error state. The routes are admin-gated at `/home/zaid/Projects/rfe-rn/agent/internal/server/settings_handlers.go:41-43` and `/home/zaid/Projects/rfe-rn/agent/internal/server/pair.go:144`.
   Source: `/home/zaid/Projects/rfe-rn/protocol/openapi.yaml:18-23`; `/home/zaid/Projects/rfe-rn/agent/internal/server/settings_handlers.go:28-35`.

9. The window must show distinct outcomes for the agent's rejection responses: INVALID_CODE, INVALID_NONCE, INVALID_SIGNATURE, DEVICE_KEY_MISMATCH, RATE_LIMITED and PAIR_BUSY.
   Accept: each code triggered against a test agent gives a different message. Limits are 10/min for /pair and /login, 6/min for /pair/request, and 3 requests waiting at once.
   Source: `/home/zaid/Projects/rfe-rn/protocol/openapi.yaml:422-428`; `/home/zaid/Projects/rfe-rn/agent/internal/server/pair.go:22-25`; `/home/zaid/Projects/rfe-rn/agent/internal/server/pair_request.go:27-32`; `/home/zaid/Projects/rfe-rn/agent/internal/server/challenge.go:153-155`.

10. Only if the approve-on-PC path (/pair/request) is chosen, the window must:
    - show the match code (HMAC-SHA256 keyed by the certificate bytes it saw);
    - poll until approved, rejected or expired (2 minutes);
    - store the token on first receipt.
    Accept: after approval, a second poll of the same request returns 404, so a test that discards the first response must fail visibly.
    Source: `/home/zaid/Projects/rfe-rn/protocol/openapi.yaml:384-394, 435-436, 457-458`; `/home/zaid/Projects/rfe-rn/agent/internal/server/pair_request.go:25, 180-188`.

11. Only if the code path (/pair) is chosen, the window must accept a one-time pairing code from the owner. The code comes from `rfe-agent pair`, from `POST /pairing/generate` by an admin session, or from the phone app's pairing screen.
    Accept: an expired or used code gives INVALID_CODE and does not burn a valid one. The agent validates the device proof before it consumes the code (`/home/zaid/Projects/rfe-rn/agent/internal/server/pair.go:78-91`).
    Source: `/home/zaid/Projects/rfe-rn/agent/internal/server/pair.go:135-147`; `/home/zaid/Projects/rfe-rn/agent/internal/webui/web/src/pages/auth/PairCode.tsx:50`.

Interfaces:

| Interface | Pair | List devices | Admin actions | Credential form |
|---|---|---|---|---|
| Agent HTTP API `/v1` (`server.go:146-152, 164, 177-180`) | `/pair` (code), `/pair/request` plus poll, `/register`, `/login` | `GET /devices`: admin gets all, non-admin gets self only | `PATCH/DELETE /devices/{id}`, `/pairing/generate`, `/pair/requests*`, `/metrics`, `/users`, `/logs`, `/audit`, `/agent/restart` need an admin device (`server.go:100-108`) | Bearer token, or `rfe_session` cookie with `X-RFE-Web-Session: 1` (`auth.go:76-94`) |
| Web companion served at "/" (`server.go:135`, `webui.go:24`) | Code only (`PairCode.tsx:18`); no `pair/request` reference found by grep in `web/src` | Devices page (`Devices.tsx:162-168`) | Generate code, patch and delete device | Same-origin HttpOnly cookie; relative `/v1` fetch (`api.ts:30-36`); Ed25519 key in IndexedDB, non-extractable (`deviceIdentity.ts:1-3`) |
| Admin CLI `rfe-agent` (`admin.go:23-65`) | `pair`, `pair requests/accept/reject` | `devices` | revoke, remove, jail, readonly, allow, backup-dir, audit, adduser, install and service commands, setup | Opens the data dir directly; no token |
| Linux desktop notification for pair requests | Approve/Reject buttons (`pairnotify_linux.go:13-15`) | n/a | n/a | n/a; the non-Linux build has no notification (`pairnotify_other.go:1,10-12`) |
| Discovery and bind | mDNS `_rfe._tcp` (`mdns.go:15`, `Discover` at :89) | n/a | n/a | Default listen ":8765"; optional ":443" listener (`main.go:70, 178`) |
| Host app catalog (`server.go:92-93`: `GET /apps`, `POST /apps/{id}/launch`) | n/a | n/a | Needs viewApps/launchApps grants; admin status gives no implicit access (`server.go:87-89`) | Bearer token |

Non-functional:

1. If the app needs any agent API change, the change must ship its `protocol/openapi.yaml` edit in the same commit.
   Accept: a diff that touches agent routes without an openapi edit fails review.
   Source: `/home/zaid/Projects/rfe-rn/CLAUDE.md:131-132`; `/home/zaid/Documents/Obsidian Vault v2/notes/rfe/references/ui-rules.md:29`.

2. The app must leave the agent's TOFU pinning and approve-on-PC pairing behaviour unchanged.
   Accept: the agent's existing pairing tests still pass, run only for the affected files per the repo's workflow.
   Source: `/home/zaid/Projects/rfe-rn/CLAUDE.md:133`.

3. Any release pipeline for the desktop app must not take the GitHub Latest flag away from the newest Android app release.
   Accept: a desktop release leaves `releases/latest/download/latest.json` pointing at the newest app release. Agent releases already use `--latest=false`.
   Source: `/home/zaid/Projects/rfe-rn/CLAUDE.md:77-78, 127-128`.

4. Tauri's updater, if used, must have signed artifacts. The researcher reports the signature "cannot be disabled" (`researcher-facts.md:7`, unchecked by me).
   Accept: whether to use the updater is open question 6.
   Source: researcher fact 5, `/tmp/claude-1000/-home-zaid/e2c64c33-9c5a-4b8a-8058-0b12b205cab1/scratchpad/researcher-facts.md:7`.

Risks:
- The slice's "lists devices" may return one row. Both /pair and approve-on-PC create non-admin devices (`pair.go:102`, `pair_request.go:200`), and a non-admin `GET /devices` returns only the caller's record (`settings_handlers.go:272-293`). A full list needs a login or register session, which needs an account (`login.go:55-62`).
- On a fresh agent, no account may exist. The only account-creation routes found are `/register` (needs a pairing code, `openapi.yaml:521`) and the `adduser` CLI (`admin.go:47`). Whether `setup` creates one: unchecked.
- Approve-on-PC is answered by a desktop notification (Linux only), the CLI, or an admin session (`pair_request.go:2-3`, `pairnotify_other.go:10-11`). A Tauri window that pairs through /pair/request has no approver on non-Linux hosts unless a CLI or admin session exists. An admin session needs login first.
- `POST /pair/request` is unauthenticated (`openapi.yaml:396`). It is limited to 6/min and 3 waiting (`pair_request.go:27-29`, `openapi.yaml:394`), so another local process could occupy the waiting slots.
- `/login` rejects a known device id presenting a different key (`challenge.go:114-120`, `openapi.yaml:36-38`). If the window loses its key or changes its device id, login fails with DEVICE_KEY_MISMATCH until it re-pairs.
- Web-session mode is built for same-origin use. The cookie is Secure, SameSite=Strict and Path=/v1 (`auth.go:36-39`), and the Origin must be https and equal r.Host (`auth.go:62-65`). The SPA calls relative `/v1` (`api.ts:32`). Whether a Tauri-bundled page can satisfy this is unchecked.
- A Tauri webview that loads the agent's page inherits the agent's CSP, which includes `connect-src 'self'` (`webui.go:37-38`). Whether the webview trusts the agent's self-signed cert is unconfirmed (`researcher-facts.md:16`).
- Pinning in Tauri is unconfirmed. `acceptInvalidCerts` exists on the http plugin (`researcher-facts.md:10`), and reqwest says trusting invalid certs trusts any certificate for any site (`researcher-facts.md:12`). The custom-verifier route is a hypothesis only (`researcher-facts.md:16`).
- The scout map's route list omits `/apps` and `/apps/{id}/launch` (`server.go:92-93`), `/logs` and `/agent/restart` (`server.go:106, 108`), and `/wol` (`server.go:176`). If "PC control" includes app launch, `architecture-review.md:26` says: host-owned catalog IDs, per-device grants, no elevation, audit, and no turning it into process execution.
- Whether each global-policy route enforces admin status is unverified (`open-findings.md:8`). An app that trusts server enforcement inherits that gap.
- The repo documents two components plus the contract and no desktop component (`CLAUDE.md:7-13`), and sets Android-first (`CLAUDE.md:127`). The desktop app's home and release tags are not specified.
- The Tauri latest stable is 2.12.1; Tauri 3 exists only as alpha (`researcher-facts.md:3`, researcher-checked). Linux needs libwebkit2gtk-4.1 for deb (`researcher-facts.md:4`). Minimum webkit2gtk and WebView2 versions are unconfirmed (`researcher-facts.md:16`).
- The UI rules (tokens only, no hardcoded colours, shared CSS off limits, `ui-rules.md:9-13`) bind web-companion edits. Whether they bind a new Tauri frontend is unstated.
- The `admin.go:402-403` comment about PATCH is wrong for admin callers (see Conflicts). A client written from that comment would omit a supported route.

Assumed:
- Tauri 2 stable, not the Tauri 3 alpha.
- Both Windows and Linux are targets, because the agent runs on both (`CLAUDE.md:11`). The owner has not said.
- The window keeps its device key and token across restarts, so the owner pairs once.
- The window supplies a stable `deviceId` (the phone uses a hardware-stable ID, `pair.go:30-31`).
- The slice only reads. It does not change settings, devices or files.
- The Tauri app sets a CSP and least-privilege capabilities. Tauri enables CSP only when configured (`researcher-facts.md:13`), but no source in the material requires it.
- The desktop app is bound by the phone's TOFU trust model (requirement 6 rests on this).
- "The read-only agents" means the requirements agent plus the scout and researcher helpers used for this spec.

Open questions:
1. Tauri wrapping the existing web companion vs a new frontend (owner-listed, unresolved). Options:
   - (a) Point the webview at the agent-served UI. This reuses the same-origin cookie and agent CSP. The web UI has no `/pair/request` client, and webview trust of the self-signed cert is unconfirmed.
   - (b) Bundle the existing `webui/web` SPA. The base URL for the relative `/v1` calls changes, as does cookie mode vs bearer, and the key moves from IndexedDB to wherever the webview keeps it.
   - (c) A new frontend. This reimplements the identity proof and states, and leaves the ui-rules question open.
   - The choice decides what requirement 6 can use.
2. Local agent vs remote-only (owner-listed, unresolved). Options:
   - (a) Local only: loopback, no discovery, and the app might use the data dir the way the CLI does.
   - (b) Remote-only: needs address entry or mDNS, and TOFU over a network.
   - (c) Both.
   - The choice changes requirement 4, the meaning of approve-on-PC, and the threat model.
3. Does "lists devices" mean the full list (needs a login session, so the account question enters the slice) or whatever the paired token returns (one row)? This changes whether login belongs in the slice and what requirement 7 accepts.
4. Which pairing path does the slice use: pairing code, approve-on-PC, or login? Each needs a different helper (CLI or admin session to mint the code, a notification or approver, an existing account). It decides whether requirement 10 or 11 applies.
5. What does "PC control" cover beyond the slice: device management (jail, read-only, revoke), approving pair requests, files and transfers, settings, app catalog and launch, WOL or agent restart, tray or background use? This sets requirement 1's scope.
6. Which operating systems and packaging does the app target: Windows, Linux or both, which installers, signed or not, and does it use the updater? See non-functional 3 and 4.
7. Where does the desktop app keep the device key and token: OS keystore, app data, or webview storage? The phone uses Keychain/Keystore (`CLAUDE.md:91-92`) and the web companion uses an HttpOnly cookie plus a non-extractable key. This changes requirement 5's storage and the token-exposure risk.
8. For the trial: which metrics decide "beats inline", and how many runs? The precedent measured one task and not the inline cost (`requirements-agent-2026-10-02.md:8-9`).
9. Is changing the agent API in scope for this app, for example a loopback-only pairing aid? In scope makes non-functional 1 live. Out of scope confines the app to the existing routes.
10. Where does the app's code live: inside `rfe-rn`, or a separate repo? This sets the release tags and CI behind non-functional 3.

Conflicts:
- `admin.go` says `PATCH /v1/devices/{id}` "now returns 403 for all app callers" (`/home/zaid/Projects/rfe-rn/agent/cmd/agent/admin.go:402-403`); `setDeviceJailHandler` returns 403 only when the caller is not an admin device (`/home/zaid/Projects/rfe-rn/agent/internal/server/settings_handlers.go:375-378`).
- `ui-rules.md` says the web companion is single-file vanilla HTML/CSS/JS with no frameworks and no build step (`/home/zaid/Documents/Obsidian Vault v2/notes/rfe/references/ui-rules.md:6`); `webui.go` and `CLAUDE.md` say it is a Vite + React + TypeScript SPA built into dist/ (`/home/zaid/Projects/rfe-rn/agent/internal/webui/webui.go:3-5`; `/home/zaid/Projects/rfe-rn/CLAUDE.md:119-121`).
- `login.go` says login grants exactly the same access any paired device already has (`/home/zaid/Projects/rfe-rn/agent/internal/server/login.go:5-8`); `isAdminDevice` and the openapi description give login/register devices admin rights that /pair devices lack (`/home/zaid/Projects/rfe-rn/agent/internal/server/settings_handlers.go:28-35`; `/home/zaid/Projects/rfe-rn/protocol/openapi.yaml:18-23`).
- The openapi description and the architecture review name Flutter as the mobile client (`/home/zaid/Projects/rfe-rn/protocol/openapi.yaml:6`; `/home/zaid/Documents/Obsidian Vault v2/notes/rfe/references/architecture-review.md:7`); `CLAUDE.md` names React Native (Expo) as the replacement for Flutter (`/home/zaid/Projects/rfe-rn/CLAUDE.md:9-10`).

Unchecked:
- The researcher's Tauri facts were not re-fetched; I have no web access. Only the scratchpad lines were read. The researcher marks facts 1, 4, 5 and 8 as re-read.
- I did not read these in full: `register.go`, `store/devices.go` beyond the grep lines, the remaining `web/src` pages (`Files`, `Settings`, `Transfers`, `Users`, `Logs`, `Overview`), and openapi outside lines 1-100, 376-515 and 1585-1655. That also covers whether `/register` mints a viaLogin token (openapi:18-20 says so; scout says `viaLogin=true`; not checked in code).
- I did not check whether `setup` creates a login account, whether `GET /health` details change with a cookie session, or how the cert is loaded at `main.go:~300`.
- I did not run the agent or any test. All Accept lines are untested.
- The scout's "not covered" items stand: cookie vs bearer for the web UI session, and how a browser treats the self-signed cert.
- The prior trial's 41-requirement Tauri brief was not found in the vault by grep for "Tauri". Only the decision note mentions it.
- The line `webListenAddr` sits at `main.go:178` and `OnPairRequest` at `main.go:349`; I did not read the rest of `main.go`.
- Not covered: none by area; no area was given.