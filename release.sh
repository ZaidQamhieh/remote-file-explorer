#!/usr/bin/env bash
#
# release.sh — build the Android release APK and publish it to the agent's
# update channel so the phone can update itself over Wi-Fi/Tailscale (no cable).
#
# Usage:
#   ./release.sh                      # build current pubspec version, publish
#   ./release.sh 1.2.0+4              # bump pubspec to this version first, then build+publish
#
# After running, open the app on the phone -> "Update available" -> tap -> install.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$REPO_DIR/app"
PUBSPEC="$APP_DIR/pubspec.yaml"
UPDATES_DIR="${RFE_UPDATES_DIR:-$HOME/.rfe-agent/updates}"
FLUTTER="${FLUTTER_BIN:-$HOME/flutter/bin/flutter}"

# Optional: bump the version in pubspec first (arg form X.Y.Z+N).
if [[ "${1:-}" != "" ]]; then
  NEW_VERSION="$1"
  if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
    echo "error: version must look like X.Y.Z+N (e.g. 1.2.0+4)" >&2
    exit 1
  fi
  # Replace the first 'version:' line in pubspec.
  sed -i -E "s/^version:.*/version: $NEW_VERSION/" "$PUBSPEC"
  echo "Bumped pubspec version -> $NEW_VERSION"
fi

# Parse versionName (X.Y.Z) and versionCode (N) from pubspec: 'version: X.Y.Z+N'.
VERSION_LINE="$(grep -E '^version:' "$PUBSPEC" | head -1 | awk '{print $2}')"
VERSION_NAME="${VERSION_LINE%%+*}"
VERSION_CODE="${VERSION_LINE##*+}"

if [[ "$VERSION_NAME" == "$VERSION_LINE" || -z "$VERSION_CODE" ]]; then
  echo "error: pubspec version '$VERSION_LINE' must include a build number (X.Y.Z+N)" >&2
  echo "       OTA update detection compares the build number — it must increase each release." >&2
  exit 1
fi

echo "Building release APK: v$VERSION_NAME (build $VERSION_CODE)…"
( cd "$APP_DIR" && "$FLUTTER" build apk --release )

SRC="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
DEST="$UPDATES_DIR/rfe-${VERSION_NAME}-${VERSION_CODE}.apk"

mkdir -p "$UPDATES_DIR"
# Remove older rfe-*.apk so the channel only advertises the newest (optional tidy).
find "$UPDATES_DIR" -maxdepth 1 -name 'rfe-*.apk' ! -name "$(basename "$DEST")" -delete 2>/dev/null || true
cp "$SRC" "$DEST"

echo
echo "Published -> $DEST"
echo "Phone (if on an older build) will now offer v$VERSION_NAME on next launch /"
echo "via host menu -> Check for updates. No cable needed."
