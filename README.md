# Remote File Explorer

A mobile app that turns your phone into a full graphical file explorer for your Windows, macOS, and
Linux computers — browse, manage, and transfer files over a Finder/Explorer-style GUI, with no SSH
or terminal required.

- **`app/`** — Flutter mobile app (Android-focused)
- **`agent/`** — Go host service that runs on each Windows/macOS/Linux computer
- **`protocol/`** — OpenAPI 3 contract shared by both sides (source of truth)
- **`docs/`** — architecture and setup guides

Remote access is handled by **Tailscale** (both phone and computer join the same tailnet), so there
is no cloud server and no cloud database. The agent is reachable on the LAN or over Tailscale by
IP/hostname, and auto-discoverable via mDNS. See `docs/` for the full architecture.

## Status

The agent serves the full v1 API: directory browsing, file transfer (resumable chunked
upload/download), search, thumbnails/previews, settings, paired-device management, and in-app
Android updates (`/v1/app/latest` + `/v1/app/download`). The Flutter app (currently v1.42.x) covers
all of the above with a Finder/Explorer-style UI and self-updates over the air.

## Pairing

Pairing is done from the host side with the agent's admin CLI:

```sh
rfe-agent pair         # mints a one-time pairing code + prints a QR in the terminal
```

Scan the QR from the app (Add computer → Scan QR), or enter the address and pairing code manually.
Pairing is TOFU (trust-on-first-use) cert pinning + a per-device bearer token — no cloud account.

## Quick start (agent)

```sh
cd agent
go run ./cmd/agent            # serves https://<host>:8765/v1/health
```

The first run generates a self-signed TLS certificate and prints its SHA-256 fingerprint (the value
the phone pins when pairing). Then run `rfe-agent pair` (or `go run ./cmd/agent pair`) to add a
device — see `docs/development.md` for the full dev workflow.

## Server setup (auto-start)

To have the agent start automatically on login instead of running it manually every time:

```sh
rfe-agent install      # registers a per-user auto-start entry, no admin/root needed
rfe-agent uninstall    # removes it
```

This sets up a systemd `--user` service on Linux, a launchd agent on macOS, or a Scheduled Task on
Windows — whichever matches the OS it's run on. The web companion (status, transfers, users, logs,
device management) is served by the same agent process at `https://<host>:8765/`, so there's
nothing else to install.
