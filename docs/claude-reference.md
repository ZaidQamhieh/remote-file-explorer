# Release and CI reference (moved out of CLAUDE.md, text unchanged)

## Release (OTA APK)

The Android app is `mobile/` (React Native). Set `expo.version` and
`expo.android.versionCode` in `mobile/app.json` (the code **must increase every release**: OTA detection compares
`versionCode`, and it started above the Flutter build's 80 and is 81 for v2.0.0), commit, push, then tag `vX.Y.Z` (becomes the Latest
release) or `vX.Y.Z-rc.N` (pre-release, never Latest) and push the tag. `.github/workflows/release.yml` runs the CI
gates, builds and signs the APK with the production key from repo secrets, checks the signing certificate, and
publishes the GitHub Release plus `latest.json` that the app's updater reads (`releases/latest`). A push to an
`rn/**` branch runs the same pipeline as a dry run and keeps the APK as a workflow artifact. Agent releases
(`agent-v*`) are published with `--latest=false`: the updater needs the newest *app* release to hold the Latest flag.
Local signed build: `mobile/scripts/build-release-apk.sh`. See `docs/upgrade-to-react-native.md`.

## CI path filters

CI runs per area: on branch pushes `release.yml` (APK build) only runs when `mobile/**`, `protocol/**`,
`.github/actions/**` or the release/mobile workflows change, `ci.yml` (agent gates) when `agent/**`, `agent-rs/**` or
`tools/**` change, `desktop.yml` for `desktop/**`; a tag always runs everything (path filters are not evaluated for tags).

## Desktop app (Tauri, `desktop/`)

PC control app for the local agent; not part of the Android release (`desktop.yml` is its gate). No desktop release
exists yet; `desktop-release.yml` (Linux deb, AppImage, SBOM, SHA256SUMS, provenance) publishes one from a `desktop-v*` tag.

Versioning: `desktop/src-tauri/Cargo.toml` and `tauri.conf.json` carry the same version (`desktop/src-tauri/tests/versions.rs`
fails when they differ). A release is the tag `desktop-vX.Y.Z` (`desktop-vX.Y.Z-rc.N` for a pre-release) on a commit with
that version, published with `--latest=false` like `agent-v*`, because the Android updater needs the newest *app* release to
hold the Latest flag. `release.yml` only runs for `v*` tags, so `desktop-v*` never starts an APK build.

Docs: `desktop/README.md`, `desktop/docs/user-guide.md` (troubleshooting), `keystore.md`. A message the user can see needs a row there;
`desktop/src-tauri/tests/docs.rs` fails for an agent error code without one and lists the app's own messages by stem.

## Background

The Flutter app (v1.42.x) that the React Native app replaced is in git history at tag `v1.42.5`.
