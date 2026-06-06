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

First run writes `agent-cert.pem` / `agent-key.pem` to the OS config dir
(`-data <dir>` to override) and logs the cert fingerprint the phone pins.

Smoke test:

```sh
curl -sk https://127.0.0.1:8765/v1/health
```

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
agent/cmd/agent/   main + (later) service install
agent/internal/    server, fsops, transfer, search, thumbs, pairing, discovery, store, security
protocol/          openapi.yaml (shared contract)
```
