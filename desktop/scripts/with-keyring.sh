#!/bin/sh
# Runs a command inside a private D-Bus session with an unlocked, empty Secret Service
# (gnome-keyring), so tests can use the real OS keystore on a headless machine or in CI.
#
#   desktop/scripts/with-keyring.sh cargo test --locked --test keystore -- --ignored
#
# Everything lives in a temporary XDG_DATA_HOME: the keyring files of the user running this are
# neither read nor written, and the daemon dies with the session. No display is passed on, so the
# keyring can never open a prompt window on the desktop of whoever runs this.
# Needs dbus-run-session, gnome-keyring-daemon and secret-tool (libsecret-tools).
set -eu

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 2
fi
for tool in dbus-run-session gnome-keyring-daemon secret-tool; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$0: $tool not found" >&2; exit 127; }
done

XDG_DATA_HOME=$(mktemp -d)
export XDG_DATA_HOME
unset DISPLAY WAYLAND_DISPLAY
trap 'rm -rf "$XDG_DATA_HOME"' EXIT INT TERM

dbus-run-session -- sh -c '
  # An empty password creates and unlocks the default keyring non-interactively.
  eval "$(printf "" | gnome-keyring-daemon --unlock --components=secrets)"
  export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK
  # The default keyring is created on first use; do that now so the first test does not race it.
  printf x | secret-tool store --label=rfe-prime rfe prime
  secret-tool clear rfe prime
  "$@"
' sh "$@"
