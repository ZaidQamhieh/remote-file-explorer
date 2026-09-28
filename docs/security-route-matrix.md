# Agent security route matrix

Reviewed against `agent/internal/server/server.go` and its handlers on 2026-09-28.
This is a code review map, not a claim that the host is ready for public exposure.

## Authentication classes

| Class | Meaning |
| --- | --- |
| Public bootstrap | No bearer token. Only health probing, identity challenge, pairing/account bootstrap, and the one-time share fetch are mounted this way. |
| Paired device | Valid, non-revoked bearer token. The request gets the device's jail and read-only state in middleware. |
| Owner device | A paired device minted through password login/registration (`via_login`). Owner-only handlers use `adminOnly` or a handler-level `isAdminDevice` check. |
| App grant | Paired device plus the stored `viewApps` and, for launch, `launchApps` flags. Owner provenance does not implicitly grant these flags. |
| Transfer/share owner | The device that created the session/link, or an owner device. Other devices receive the same 404 as an unknown ID. |

## Routes and gates

| Route(s) | Gate and scope | Sensitive behavior / review note |
| --- | --- | --- |
| `GET /v1/health` | Public minimal response; valid bearer may receive the additional host details | Does not expose topology details to an unauthenticated caller. |
| `POST /v1/auth/challenge`, `/pair`, `/register`, `/login` | Public bootstrap; nonce/pairing constraints and rate limits apply where implemented | Pairing/account credentials must be sent over the agent's HTTPS listener; the app pins the host certificate before sending them. |
| `GET /v1/share/{token}` | Public, single-use, expiring random token, per-IP rate-limited | The handler rechecks the current global path jail, opens and validates a regular file, limits the response to the checked size, and sets download-safe browser headers. This is the only intentionally public content route. |
| `GET /v1/status` | Any paired device | Returns agent version, uptime, platform, and data-volume capacity. |
| `GET /v1/transfers/list`, `GET/DELETE /v1/transfers/{id}` | Paired device; list and individual rows are scoped to the creator, with owner access | Foreign IDs are hidden as 404. Upload creation/chunk/completion additionally require writable effective policy. |
| `GET /v1/apps` | `viewApps` grant | Catalog is separate from launch permission. |
| `POST /v1/apps/{id}/launch` | Both `viewApps` and `launchApps`; opaque ID re-resolved from the current native catalog; rate and concurrency limits; audit event | No client command, executable path, or arguments are accepted. GUI session and platform checks apply. |
| `GET /v1/metrics`, `/users`, `/logs`, `/audit`; `DELETE /v1/users/{username}`; `POST /v1/agent/restart` | Owner device (`ViaLogin`) via `adminOnly` | Host-wide telemetry, account, audit, log, and process-control data/actions are not available to ordinary paired devices. |
| `GET /v1/settings` | Any paired device; owner sees global settings, other devices receive effective scoped settings | Non-owner response omits unrelated global paths and hides the photo backup path unless it falls within the device's effective scope. |
| `PATCH /v1/settings`, `/settings/bandwidth` read/write, `POST /v1/pairing/generate` | Owner device (handler-level checks) | Changes to global policy and creation of pairing codes are owner-only. |
| `GET /v1/devices` | Owner sees all devices; other paired devices see only a reduced self entry | The reduced response omits access-control fields and other devices. |
| `PATCH /v1/devices/{id}` | Owner device | Sets another device's jail/read-only/app grants; checks the target jail against global roots. |
| `DELETE /v1/devices/{id}` | Device can revoke/remove itself; owner can manage another device | Revocation is checked by auth middleware on the next request. `?purge=true` removes the database row. |
| `POST /v1/wol` | Paired, non-read-only device | Read-only devices cannot send Wake-on-LAN. |
| `POST /v1/share/mint`, `GET /v1/share`, `DELETE /v1/share/{tokenHash}` | Paired device; mint also needs global sharing enabled and an in-jail regular file; list/revoke are owner-scoped | Share tokens are hashed at rest and audited. No separate per-device share grant exists yet. |
| `GET /v1/system/drives`, `/search`, `/thumb`, `/fs`, `/fs/meta`, `/fs/checksum`, `/fs/archive`, `/fs/checksums`, `/fs/recent`, `GET /v1/content`, `GET /v1/trash`, `GET /v1/app/latest`, `/v1/app/download` | Any paired device, with path-based reads constrained by the effective jail | App update routes are authenticated. Path reads and media responses are served through the agent API. |
| `POST /v1/fs/folder`, `/fs/file`, `/fs/rename`, `/fs/copy`, `/fs/move`, `/fs/compress`, `/fs/extract`, `/fs/chmod`, `PUT /v1/content`, `POST /v1/trash/restore`, `DELETE /v1/fs`, `/v1/trash` | Any paired device, but mutations reject global or per-device read-only policy and path operations use the effective jail | Batch operations return per-item errors. Resumable upload routes use `requireWritable` before session/chunk handlers. |

## Authorization coverage and remaining gap

The current tests include a route-level read-only matrix for filesystem and trash mutation routes,
separate upload read-only wiring checks, owner-vs-device settings/device-management tests, app
grant checks, and transfer/share ownership checks. CI also runs race-enabled Go tests. These tests
cover the current coarse roles and policies; they do not provide a separate, machine-generated
permission declaration for every route.

The current authorization model is **not yet fine-grained per device** for filesystem actions.
Except for the read-only flag and path jail, a standard paired device can browse, download, upload,
modify, delete, and mint shares when the global share switch is enabled. Independent browse,
download, upload, modify, delete, and share grants, with matching host UI and migration behavior,
remain security work before granting devices with different trust levels. The code also retains a
path-based filesystem jail check; a local process able to race filesystem components may exploit
time-of-check/time-of-use gaps until descriptor-relative operations replace the check-then-open
pattern. See the filesystem hardening work and its platform-specific verification before treating
that item as closed.

## Transport and reachability

The agent serves HTTPS only; the main listener defaults to port 8765 and a best-effort HTTPS
listener may also bind port 443. There is no plaintext HTTP mode. The mobile app pins the agent
certificate independently of whether the address is LAN, Tailscale, or owner-configured direct
HTTPS. The application does not configure router forwarding, DNS, firewall rules, or a relay.
Direct internet reachability therefore remains an explicit host-owner network setup.
