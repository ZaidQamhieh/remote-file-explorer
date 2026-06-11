# Architecture

## Overview

Two components plus a shared contract:

- **`app/`** — Flutter mobile app (Android-focused, v1.5+). All UI + client orchestration.
- **`agent/`** — Go host service on each Windows/Linux computer. Owns filesystem access, the
  transfer engine, search, thumbnails, settings, and the device/token store.
- **`protocol/openapi.yaml`** — the REST contract both sides follow (source of truth).

The app talks to the agent over **HTTPS (HTTP/2) + TLS**, reachable on the LAN by IP or, from
anywhere, via the computer's **Tailscale** address — same code path. mDNS auto-discovery on the
LAN is not implemented (`agent/internal/discovery` is an empty placeholder package). Because
Tailscale (WireGuard) already provides NAT traversal, stable addressing, and encryption, there is
**no cloud server and no cloud database**.

## Key decisions

| Area | Decision |
|------|----------|
| Mobile framework | Flutter (Riverpod, dio, flutter_secure_storage) |
| Backend | Custom Go host agent — single static binary, runs as a service |
| Remote access | Tailscale (already in use) + LAN by IP/hostname; mDNS planned, not implemented |
| Transport security | TLS with self-signed cert; phone pins the SHA-256 fingerprint at pairing (TOFU) |
| Storage | SQLite on the agent; local DB + Keychain/Keystore on the phone |

## Security model (summary)

1. TLS everywhere; fingerprint pinning on top of Tailscale's WireGuard layer.
2. Device pairing (via `rfe-agent pair`, QR or manual entry) issues a revocable bearer token
   (stored in Keychain/Keystore on the phone).
3. Per-agent authorization: root-path jail, optional read-only mode, device revocation/removal,
   `/pair` rate limiting (10/min).
4. Strict path normalization + jail enforcement against traversal/symlink escape.

There is currently no audit log — device actions (revoke/remove, settings changes) are not
recorded to a persistent log; this is a possible future addition.

## Transfers (the core engineering)

- **Upload:** resumable chunked sessions. Per-chunk + whole-file SHA-256; received-chunk bitmap in
  SQLite for resume; atomic temp→final rename on completion. Chunks can upload in parallel.
- **Download:** HTTP Range requests; resume from last offset; optional parallel ranges.

See `../protocol/openapi.yaml` for the full API surface and the design doc for the phase roadmap.
