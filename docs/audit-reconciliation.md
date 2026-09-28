# Legacy audit reconciliation

Reviewed against the current source on 2026-09-28. This note reconciles the
security and performance items carried in the project notes; it is not a new
penetration test or a release approval.

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
| Trash IDs were joined into paths and passed to recursive deletion. | Fixed in the current source. IDs are validated as opaque values, and restore/delete operations resolve through the trash store and rooted filesystem APIs. | `agent/internal/fsops/trash.go`; server trash handler tests; route summary in `docs/security-route-matrix.md`. |
| Any paired device could change host-wide policy. | Fixed for the reviewed host-wide routes. Settings, bandwidth, pairing-code creation, and other owner operations use `adminOnly` or explicit owner-device checks. | `agent/internal/server/server.go`; `agent/internal/server/settings_handlers.go`; route and authorization coverage in `docs/security-route-matrix.md`. |

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

## Verification on this revision

Commit `63fe8b16` passed all 10 GitHub CI jobs: Go race tests, coverage floor,
vet, vulnerability scan, Flutter analyze/tests, six host builds, OpenAPI, and
the web companion build/lint. Local verification also passed the complete Go
server test package, the focused recent-scan concurrency regression, OpenAPI
validation, and the Obsidian vault integrity check.
