# Agent security route matrix

Reviewed against `agent/internal/server/server.go` and its handlers on 2026-09-28.
This is a code review map, not a claim that the host is ready for public exposure.

## Authentication classes

| Class | Meaning |
| --- | --- |
| Public bootstrap | No bearer token. Only health probing, identity challenge, pairing/account bootstrap, and the one-time share fetch are mounted this way. |
| Paired device | Valid, non-revoked bearer token. The request gets the device's jail and read-only state in middleware; file routes also check required per-device capabilities. |
| Owner device | A paired device minted through password login/registration (`via_login`). Owner-only handlers use `adminOnly` or a handler-level `isAdminDevice` check. File capability gates are bypassed for owner devices; global policy and effective path roots remain in force. |
| File capability | One of `browse`, `download`, `upload`, `modify`, `delete`, or `share`. Missing grants return 403 `CAPABILITY_DENIED`; grants never confer owner/admin privileges. |
| App grant | Paired device plus the stored `viewApps` and, for launch, `launchApps` flags. Owner provenance does not implicitly grant these flags. |
| Transfer/share owner | The device that created the session/link, or an owner device. Other devices receive the same 404 as an unknown ID. |

## Routes and gates

| Route(s) | Gate and scope | Sensitive behavior / review note |
| --- | --- | --- |
| `GET /v1/health` | Public minimal response; valid bearer may receive the additional host details | Does not expose topology details to an unauthenticated caller. |
| `POST /v1/auth/challenge`, `/pair`, `/register`, `/login` | Public bootstrap; nonce/pairing constraints and rate limits apply where implemented | Pairing/account credentials must be sent over the agent's HTTPS listener; the app pins the host certificate before sending them. |
| `GET /v1/share/{token}` | Public, single-use, expiring random token, per-IP rate-limited | The handler rechecks the current global path jail, opens and validates a regular file, limits the response to the checked size, and sets download-safe browser headers. This is the only intentionally public content route. |
| `GET /v1/status` | Any paired device | Returns agent version, uptime, platform, and data-volume capacity. |
| `GET /v1/transfers/list`, `GET/DELETE /v1/transfers/{id}` | Paired device; list and individual rows are scoped to the creator, with owner access | Foreign IDs are hidden as 404. Upload creation/chunk/completion additionally require `upload` and writable effective policy. |
| `GET /v1/apps` | `viewApps` grant | Catalog is separate from launch permission. |
| `POST /v1/apps/{id}/launch` | Both `viewApps` and `launchApps`; opaque ID re-resolved from the current native catalog; rate and concurrency limits; audit event | No client command, executable path, or arguments are accepted. GUI session and platform checks apply. |
| `GET /v1/metrics`, `/users`, `/logs`, `/audit`; `DELETE /v1/users/{username}`; `POST /v1/agent/restart` | Owner device (`ViaLogin`) via `adminOnly` | Host-wide telemetry, account, audit, log, and process-control data/actions are not available to ordinary paired devices. |
| `GET /v1/settings` | Any paired device; owner sees global settings, other devices receive effective scoped settings | Non-owner response omits unrelated global paths and hides the photo backup path unless it falls within the device's effective scope. |
| `PATCH /v1/settings`, `/settings/bandwidth` read/write, `POST /v1/pairing/generate` | Owner device (handler-level checks) | Changes to global policy and creation of pairing codes are owner-only. |
| `GET /v1/devices` | Owner sees all devices; other paired devices see only a reduced self entry | The reduced response omits access-control fields and other devices. |
| `PATCH /v1/devices/{id}` | Owner device | Sets another device's jail/read-only, app, and file-action grants; checks target jail against global roots. Disabling `share` deletes active tokens minted by that device. |
| `DELETE /v1/devices/{id}` | Device can revoke/remove itself; owner can manage another device | Revocation is checked by auth middleware on the next request. `?purge=true` removes the database row. |
| `POST /v1/wol` | Paired, non-read-only device | Read-only devices cannot send Wake-on-LAN. |
| `POST /v1/share/mint` | `share` + `browse`, global sharing enabled, and an in-jail regular file; owner bypasses the grants | Share tokens are hashed at rest and audited. Disabling a device's share grant deletes its active links. Public tokens remain one-use bearer credentials until used or revoked. |
| `GET /v1/share`, `DELETE /v1/share/{tokenHash}` | Paired device; list/revoke are owner-scoped | Devices can still inspect/revoke existing links after the share-mint grant is removed. |
| `GET /v1/system/drives`, `/search`, `/fs`, `/fs/meta`, `/fs/archive`, `/fs/recent`, `GET /v1/trash` | `browse`; path operations constrained by the effective jail | Directory, metadata, search, archive-entry and trash discovery. |
| `GET /v1/thumb`, `/fs/checksum`, `POST /v1/fs/checksums`, `GET /v1/content` | `download`; path reads constrained by the effective jail | Thumbnails/checksums are byte-derived reads. `/app/latest` and `/app/download` are authenticated agent-update routes, not user-file downloads. |
| `PUT /v1/content`, `POST /v1/transfers`, `PUT /v1/transfers/{id}/chunks/{n}`, `POST /v1/transfers/{id}/complete` | `upload`, writable effective policy, and effective jail | Content writes and resumable uploads. Upload covers overwrites too; there is no separate `modify` check for replacing an existing target because the transfer engine owns that decision. |
| `POST /v1/fs/folder`, `/fs/file`, `/fs/rename`, `/fs/copy`, `/fs/compress`, `/fs/extract`, `/fs/chmod`, `POST /v1/trash/restore` | `modify`, writable effective policy, and effective jail | Copy is modify-only; restore is classified as modify. Batch handlers can return per-item errors after route authorization. |
| `POST /v1/fs/move` | `modify` + `delete`, writable effective policy, and effective jail | Moving changes the destination and removes the source. |
| `DELETE /v1/fs`, `/v1/trash` | `delete`, writable effective policy, and effective jail | Includes filesystem deletion and empty-trash. |

## Authorization coverage and remaining gap

Tests include route-level read-only and per-device file-capability matrices, migration/default
tests, owner-vs-device settings/device-management tests, app grant checks, and transfer/share
ownership checks. This route map is hand-maintained alongside route registration.

The migration preserves prior access for existing devices: browse, download, and share remain
enabled; upload, modify, and delete remain enabled only for devices that were not read-only.
Newly paired devices start browse-only. Login/register owner devices retain full file access and
bypass per-device file grants; configured roots, global/per-device read-only, and per-device jail
remain effective. One limitation remains: upload authorization also permits overwriting because
the transfer engine's overwrite check is not separately wired to the `modify` grant. Share links
are public one-use bearer credentials; disabling a device's share grant deletes its outstanding
tokens, but changing its jail does not retroactively change links already minted. The code also
retains a path-based filesystem jail check; a local process able to race filesystem components
may exploit time-of-check/time-of-use gaps until descriptor-relative operations replace the
check-then-open pattern.

## Transport and reachability

The agent serves HTTPS only; the main listener defaults to port 8765 and a best-effort HTTPS
listener may also bind port 443. There is no plaintext HTTP mode. The mobile app pins the agent
certificate independently of whether the address is LAN, Tailscale, or owner-configured direct
HTTPS. The application does not configure router forwarding, DNS, firewall rules, or a relay.
Direct internet reachability therefore remains an explicit host-owner network setup.
