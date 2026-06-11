# Development setup

## Toolchain

- **Flutter** 3.29 / Dart 3.7 (already installed at `~/flutter`).
- **Go** 1.26 installed at `~/.local/go`. Add it to your PATH (e.g. in `~/.bashrc`):

  ```sh
  export PATH="$HOME/.local/go/bin:$PATH"
  ```

## Agent

```sh
cd agent
go vet ./...
go build -o bin/agent ./cmd/agent
go run ./cmd/agent -addr 127.0.0.1:8765 -name "my-pc"
```

First run writes `agent-cert.pem` / `agent-key.pem`, the SQLite DB, and other state into the
**data dir**, and logs the cert fingerprint the phone pins. The data dir is resolved with this
precedence: `-data <dir>` flag > `$RFE_DATA_DIR` env var > `~/.rfe-agent` (default). The admin CLI
(below) resolves the data dir the same way, so `rfe-agent devices` (no flags) talks to the same DB
as a no-args `rfe-agent` daemon.

Smoke test:

```sh
curl -sk https://127.0.0.1:8765/v1/health
```

### Pairing a device

Pairing codes are minted by the admin CLI, not printed by the running daemon:

```sh
go run ./cmd/agent pair         # mints a one-time code + prints a QR in the terminal
go run ./cmd/agent devices       # list paired devices
go run ./cmd/agent revoke <id>   # block a device
go run ./cmd/agent remove <id>   # permanently delete a device row
go run ./cmd/agent status        # name, addresses, fingerprint, device counts
```

Scan the QR from the app (Add computer → Scan QR), or enter the address + code manually. These
subcommands work whether or not the daemon is running, since they open the same on-disk DB
directly (with a busy-timeout so concurrent daemon + CLI writes are safe).

## App

```sh
cd app
flutter pub get
flutter analyze
flutter run        # enter the agent's host:port on the connection screen
```

Note: the app pins the agent's self-signed cert by fingerprint via
`HttpClient.badCertificateCallback`, so it works without a public CA. On the first connection the
fingerprint is captured (trust on first use); afterwards a mismatch is rejected.

## Layout

```
app/lib/core/      api client, models, storage
app/lib/features/  hosts, explorer, transfers, preview, pairing, settings
agent/cmd/agent/   main (daemon) + admin.go (pair/devices/revoke/remove/status CLI)
agent/internal/    server, fsops, transfer, search, thumbs, pairing, store, security, settings, updates
agent/internal/discovery/  empty placeholder — mDNS not implemented
protocol/          openapi.yaml (shared contract)
```
