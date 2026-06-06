# Remote File Explorer

A cross-platform mobile app that turns your phone into a full graphical file explorer for your
Windows and Linux computers — browse, manage, and transfer files over a Finder/Explorer-style GUI,
with no SSH or terminal required.

- **`app/`** — Flutter mobile app (iOS-first, Android too)
- **`agent/`** — Go host service that runs on each Windows/Linux computer
- **`protocol/`** — OpenAPI 3 contract shared by both sides (source of truth)
- **`docs/`** — architecture and setup guides

Remote access is handled by **Tailscale** (both phone and computer join the same tailnet), so there
is no cloud server and no cloud database. On the local network the agent is also discoverable via
mDNS. See `docs/` for the full architecture.

## Status

Phase 0 — foundations. The agent serves a TLS `/health` endpoint; the Flutter app and the rest of
the API are being built out per the roadmap in the design doc.

## Quick start (agent)

```sh
cd agent
go run ./cmd/agent            # serves https://<host>:8765/v1/health
```

The first run generates a self-signed TLS certificate and prints its SHA-256 fingerprint (the value
the phone pins when pairing).
