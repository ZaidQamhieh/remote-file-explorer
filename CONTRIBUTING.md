# Contributing

Pull requests are welcome. `master` is protected: every change goes through a pull request with at
least one approving review. CI runs on every PR and should be green before it is merged.

## Before you open a PR

- Open an issue first for anything large, so the direction can be agreed.
- Keep the change small and focused; do not mix refactors with fixes.
- Run the checks for the part you changed:
  - agent (`agent/`): `go vet ./... && go test ./...`
  - Rust (`agent-rs/`, `desktop/src-tauri/`): `cargo fmt --all -- --check`, `cargo clippy --all-targets --locked -- -D warnings`, `cargo test --locked` (desktop tests need `RFE_AGENT_BIN` set to a built agent)
  - mobile (`mobile/`): `npx jest`, `npx tsc --noEmit`, `npx expo lint`
- A change to an agent route also changes `protocol/openapi.yaml` in the same PR.
- Never commit secrets, `.env` files or keystores.

## Review and merge

A maintainer reviews each PR. Collaborators with write access can approve and merge once the
required review and checks are green. Resolve all review conversations before merging.

## License

By contributing you agree that your work is licensed under the project's license
([GPL-3.0](LICENSE); the Rust sidecars in `agent-rs/` are MIT).
