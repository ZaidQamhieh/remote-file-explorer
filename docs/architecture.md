# Architecture

## Overview

Two components plus a shared contract:

- **`app/`** — Flutter mobile app (iOS-first, Android too). All UI + client orchestration.
- **`agent/`** — Go host service on each Windows/Linux computer. Owns filesystem access, the
  transfer engine, search, thumbnails, device/token store, and audit log.
- **`protocol/openapi.yaml`** — the REST contract both sides follow (source of truth).

The app talks to the agent over **HTTPS (HTTP/2) + TLS**. Reachable on the LAN (mDNS discovery)
or, from anywhere, via the computer's **Tailscale MagicDNS** name — same code path. Because
Tailscale (WireGuard) already provides NAT traversal, stable addressing, and encryption, there is
**no cloud server and no cloud database**.

## Key decisions

| Area | Decision |
|------|----------|
| Mobile framework | Flutter (Riverpod, dio, flutter_secure_storage) |
| Backend | Custom Go host agent — single static binary, runs as a service |
| Remote access | Tailscale (already in use) + LAN/mDNS locally |
| Transport security | TLS with self-signed cert; phone pins the SHA-256 fingerprint at pairing (TOFU) |
| Storage | SQLite on the agent; local DB + Keychain/Keystore on the phone |

## Security model (summary)

1. TLS everywhere; fingerprint pinning on top of Tailscale's WireGuard layer.
2. QR-code device pairing issues a revocable bearer token (stored in Keychain/Keystore).
3. Per-agent authorization: root-path jail, optional read-only mode, device revocation, audit log.
4. Strict path normalization + jail enforcement against traversal/symlink escape.

## Transfers (the core engineering)

- **Upload:** resumable chunked sessions. Per-chunk + whole-file SHA-256; received-chunk bitmap in
  SQLite for resume; atomic temp→final rename on completion. Chunks can upload in parallel.
- **Download:** HTTP Range requests; resume from last offset; optional parallel ranges.

See `../protocol/openapi.yaml` for the full API surface and the design doc for the phase roadmap.
