# Agent Admin CLI — Design Spec

Date: 2026-06-08. Status: approved (user delegated, build directly).

## Goal

Make day-to-day agent admin easy from the terminal — chiefly **minting a pairing
code on demand** (no service restart, no journal grep), plus listing/revoking/
removing devices and a status readout. Replaces the current flow where the only
way to get a code is to restart the daemon and read the rendered QR from logs.

## Architecture: DB-backed pairing codes

The pairing code currently lives only in the running daemon's memory, so a
separate CLI process can't produce one the daemon will accept. Fix by moving
codes into the SQLite DB both processes already share:

- New table `pairing_codes(code TEXT PRIMARY KEY, expires INTEGER NOT NULL)` via
  idempotent migration.
- Store methods: `CreatePairingCode(code, expires)`, `ConsumePairingCode(code)
  bool` (exists AND not expired → delete, return true; single-use), and
  best-effort expired-row cleanup on mint/consume.
- `pairing.Manager` becomes DB-backed (imports `store`; no import cycle):
  - `New(db, lan, tailscale, fingerprint)` — holds what's needed to build QR
    payloads; no longer mints/prints on construction.
  - `Mint(ttl) (code string, payload QRPayload, err error)` — generate a code,
    persist it, return the payload.
  - `Consume(code) bool` — delegates to the store.
- The daemon **no longer mints/prints a code at startup**; codes are on-demand
  via `rfe-agent pair`, so restarts stop rotating anything. The `/pair` handler
  is unchanged except `pm.Consume` is now DB-backed.

## CLI structure (backward compatible)

`cmd/agent/main.go` becomes a thin dispatcher:
- No args, or first arg starts with `-`, or first arg is `serve` → run the daemon
  (today's logic moved into `runServe(args)`). The systemd unit
  (`rfe-agent -addr 0.0.0.0:8765 -name main-pc -data ~/.rfe-agent`) keeps working
  unchanged.
- Any other first arg dispatches to a subcommand handler in new
  `cmd/agent/admin.go`. Each opens the data dir, does its work, exits non-zero on
  error.

Shared data-dir resolution for admin commands: `-data` flag > `$RFE_DATA_DIR` >
default `~/.rfe-agent` (matches the deployed service).

## Commands

- `rfe-agent pair [-ttl 1h]` — mint a code; print the code, the QR payload JSON,
  and a scannable ASCII QR in the terminal (reuse vendored `go-qrcode`). Needs
  addresses (reuse `reachableAddresses`/`netinfo`) and the cert fingerprint
  (load existing cert from data dir).
- `rfe-agent devices` — table: short id, label, status (active/revoked/this-
  device n/a here), last-seen relative.
- `rfe-agent revoke <id>` — `store.RevokeDevice`; accepts a unique id prefix.
- `rfe-agent remove <id>` — `store.DeleteDevice`; accepts a unique id prefix.
- `rfe-agent status` — agent name (config), LAN + Tailscale addresses, cert
  fingerprint, version, device count.

A small shared helper resolves a unique id prefix to a full device id (error if
ambiguous or not found).

## Testing

- Store tests: pairing-code create/consume happy path, expiry rejection,
  single-use (second consume false), prefix resolution helper.
- Light handler tests against a temp data dir where practical (devices/revoke/
  remove operate on the store).
- Existing Go suite stays green; agent rebuilt and redeployed.

## Constraints / Out of scope

- Cross-process SQLite: daemon holds WAL DB (single writer); CLI does brief
  reads/writes — WAL handles cross-process locking. Fine.
- No new network/IPC surface; no auth needed (local shell already trusted).
- Not doing: remote admin, settings edits beyond what exists, interactive TUI.
