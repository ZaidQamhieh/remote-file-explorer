# Legacy audit reconciliation

Reviewed against released master `888e1c1` on 2026-09-28. This note reconciles
the security and performance items carried in the project notes and records a
focused static review of authorization, enrollment/login transport, and
filesystem boundaries. It is not a penetration test or a release approval.

## Scope and confidence

The available 2026-07-15 audit note records an aggregate of "2 critical + 83
high/medium/low" but does not include the individual finding IDs, evidence, or
the scanner/report output. The aggregate therefore cannot be independently
recounted or marked fully closed from that note. The two named critical issues
below were checked against the current code; the remaining aggregate findings
stay unverified until the itemized report is available or a fresh audit is run.

## Named critical findings

| Previous finding | Current review | Evidence |
| --- | --- | --- |
| Trash IDs were joined into paths and passed to recursive deletion. | The specific ID traversal issue is fixed: client IDs are restricted to opaque basenames, and restore/empty operations check the recorded origin against the caller's jail. The trash store itself still uses agent-managed absolute paths outside the per-device rooted filesystem handle. | `agent/internal/fsops/trash.go`; `agent/internal/fsops/jail.go`; route summary in `docs/security-route-matrix.md`. This review did not test concurrent tampering of the host-managed store. |
| Any paired device could change host-wide policy. | Fixed for the reviewed host-wide routes. Settings, bandwidth, pairing-code creation, and other owner operations use `adminOnly` or explicit owner-device checks. | `agent/internal/server/server.go`; `agent/internal/server/settings_handlers.go`; route and authorization coverage in `docs/security-route-matrix.md`. |

## Focused review findings

| Area | Verified behavior / finding | Evidence and limits |
| --- | --- | --- |
| Host-wide administration | Metrics, users, logs, audit history, and agent restart are in the `authMiddleware` + `adminOnly` router group. Global settings mutation, bandwidth access, pairing-code minting, and management of other devices have handler-level owner checks. Password login and registration tokens are owner-level; a code-paired device is not. | `agent/internal/server/server.go`; `settings_handlers.go`; `agent_control.go`; `webdata_handlers.go`. Static route/handler review only. |
| Public enrollment/login body parsing | `/pair`, `/register`, and `/login` decoded attacker-controlled JSON without a request-size limit. They now use `decodeJSONBody`, which applies a 1 MiB cap and requires one JSON document. | `agent/internal/server/pair.go`; `register.go`; `login.go`; `server.go`. No tests were added or run. Regression tests should cover oversized and concatenated JSON on each route. |
| Per-source limiter memory | The keyed limiter advertised a 4,096-key bound but still inserted new keys if all buckets were active. It now routes previously unseen keys through a shared overflow window when the cap remains full after pruning. | `agent/internal/server/ratelimit.go`. Existing tracked sources retain individual windows; overflow sources share a budget. No test was added or run; add coverage proving the map stays capped under many distinct active keys. |
| Native TLS identity | The Flutter client blocks non-preflight requests without a valid stored pin. Pairing, registration, and login construct a client with an independently supplied fingerprint before fetching the challenge or sending codes/credentials. The agent listener is HTTPS-only with TLS 1.2 minimum. | `app/lib/core/api/agent_client.dart`; `app/lib/features/pairing/pairing_screen.dart`; `agent/cmd/agent/main.go`; `docs/host-setup.md`. A QR and fingerprint delivered together over an untrusted channel do not independently authenticate the host. |
| Browser TLS identity | Embedded companion login, pairing, and registration send credentials/codes to the current HTTPS origin, but browser JavaScript has no peer-certificate pin check. It relies on ordinary browser certificate validation. Default self-signed certificates are not browser-trusted, so browser use over an untrusted network requires a separately configured trusted certificate. | `agent/internal/webui/web/src/lib/api.ts`; `docs/host-setup.md`; clarification in `docs/security-route-matrix.md`. Do not treat bypassing a certificate warning as identity verification. |
| Path jail and trash | File paths are checked against configured roots and jailed operations use `os.Root`; per-device jail/read-only is applied after authentication. Trash IDs are basenames and restore/empty check recorded origins against the active jail. The shared trash store itself is agent-managed and uses absolute-path operations outside the per-device root. If no global roots or device jail are configured, file access is limited only by the agent process's OS permissions. | `agent/internal/fsops/jail.go`; `trash.go`; `agent/internal/server/auth.go`. Tests exist in source but were not run here. `os.Root` does not block mount/bind-mount traversal or special files. |

The focused review found no verified bypass of the reviewed host-wide admin
checks or device path-jail checks. This source review is not proof that every
route, platform, or filesystem race is secure.

## Previously reported themes checked

| Theme | Current status |
| --- | --- |
| Reachable image-decoder vulnerabilities | Dependency updates are on the modernization branch. CI `govulncheck` reports no reachable vulnerabilities. It still reports an uncalled, unmaintained `golang.org/x/crypto/openpgp` module package; that package is not imported by the agent. |
| Thumbnail request storms | Bounded and coalesced on both sides: the agent limits endpoint work and joins duplicate renders; the app deduplicates, caps concurrent fetches at four, and cancels abandoned work. |
| Search index allocation and repeated rebuild work | Each snapshot is capped at 2 million entries and an estimated 128 MiB. The previous snapshot remains live during a rebuild, so the estimate can approach twice that amount before allocator overhead. Rebuilds back off to at least ten times the previous build duration when slower than the five-minute interval. Hidden/cache paths are pruned, MIME sniffing is disabled during indexing, and root-prefix strings are prepared once per query. The index can still walk the full configured roots (or the home directory when no roots are configured), and the per-device/global root policy remains a design constraint. |
| Recent-files full-tree scan | A complete result is reused for up to five seconds for the same effective roots and limit; partial results are not cached. Cache misses still walk the selected tree with a 15-second budget. At most two scans run concurrently per agent process; overflow receives `429 RECENT_BUSY` and `Retry-After: 1`. This reduces repeated refresh scans but is not an incremental index. |
| Transfer history growth | Completed and failed upload history is pruned after 90 days. Open sessions and uploaded destination files are not removed by this retention policy. |
| Offline cache fallback | `fetchBytes` falls back to cached data only for connectivity failures; HTTP and application errors are surfaced. |
| Host online status | The host card refreshes health every minute while visible and when the app returns to the foreground, rather than relying on one startup probe. |
| Browser token handling | The companion uses a Secure, HttpOnly, SameSite=Strict session cookie, same-origin request checks, no-store API responses, and a non-extractable browser identity key in IndexedDB. A same-origin script compromise can still act through an open session. |
| Path jail and upload publication | File operations use rooted handles and per-device effective roots. `os.Root` does not prevent mount/bind-mount traversal or special files. On filesystems without hard-link support, no-overwrite publication can expose a partial destination while copying. |

## Not verified or owner-dependent

- The unitemized 83-finding portion of the July report remains unverified; do not treat the two named fixes as closure of that larger count.
- Physical Android discovery, pairing, and audio playback need a real phone. No Android device was attached during this review.
- Windows and macOS agent builds pass CI, but runtime behavior still needs acceptance on those operating systems.
- Direct internet HTTPS requires owner-managed DNS, router/firewall reachability, and a trusted certificate. Signing, Play Protect review, installer distribution, and public release also require owner accounts and decisions.
- mDNS discovery is available in the Android app; manually entering a `.local` address still depends on the client operating system's resolver. IP entry remains available.

## Prior automated verification

Commit `63fe8b16` previously passed all 10 GitHub CI jobs: Go race tests, coverage floor,
vet, vulnerability scan, Flutter analyze/tests, six host builds, OpenAPI, and
the web companion build/lint. That historical result predates released master
`888e1c1` and this focused review diff; it is not test evidence for these
changes. No tests or builds were run during this review. The July audit's
unitemized 83 findings remain unverified.
