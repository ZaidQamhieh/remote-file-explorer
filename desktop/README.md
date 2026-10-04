# RFE Desktop

A Tauri app for a PC that talks to an `rfe-agent`: it pins the agent's certificate, signs this computer
in (account, pairing code, or approval on the PC) and lists the agent's paired devices. It keeps its
secrets in the system keystore.

- Using it: [docs/user-guide.md](docs/user-guide.md) (install, trust, sign in, every message explained)
- The keystore, per provider, and its messages: [docs/keystore.md](docs/keystore.md)
- Which agent releases it works with: [docs/agent-compatibility.md](docs/agent-compatibility.md)

## Layout

| Path | What |
|---|---|
| `src-tauri/` | The Rust core. It owns every network call and every secret; the window has no network access. |
| `ui/` | The window: plain HTML, CSS and one script, no build step. |
| `ui-tests/` | Node tests that drive `ui/app.js` against a fake DOM (which screen and message, not looks). |
| `scripts/with-keyring.sh` | Runs a command against a private, real gnome-keyring. |
| `docs/` | The guides above. |

## Build and test

You need Rust (the toolchain is pinned in `src-tauri/rust-toolchain.toml`), Go (the tests build the
agent), Node, and on Linux the WebKitGTK development packages listed in
`.github/workflows/desktop.yml`.

```sh
cd desktop/src-tauri
cargo fmt --all --check
cargo clippy --all-targets --locked -- -D warnings
RFE_AGENT_BIN=/path/to/rfe-agent cargo test --locked    # go build -o /path/to/rfe-agent ./cmd/agent, in agent/
node --test ../ui-tests/*.test.mjs
```

The tests start throwaway agents on random ports with temporary data folders and no desktop
notification or session bus, so nothing reaches your screen or your keyring. The tests that need a real
Secret Service run through `scripts/with-keyring.sh` (see [docs/keystore.md](docs/keystore.md)).

Run the app: `cargo run` in `desktop/src-tauri`. Package it: `cargo tauri build --bundles deb,appimage`
(`cargo install tauri-cli --version 2.12.1 --locked` once). Versioning and tags: the "Desktop app"
section of the repository's `CLAUDE.md`.
