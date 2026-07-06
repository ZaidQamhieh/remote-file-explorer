package main

import (
	"fmt"
	"os"
	"path/filepath"
)

// cmdInstall sets up the agent to auto-start at login, per-user and with no
// root/admin required: a systemd --user unit on Linux, a launchd
// LaunchAgent on macOS, or a Scheduled Task on Windows. See
// install_linux.go / install_darwin.go / install_windows.go for the
// platform-specific installService/uninstallService implementations.
func cmdInstall(args []string) error {
	exe, err := resolveExecutable()
	if err != nil {
		return err
	}
	return installService(exe)
}

// cmdUninstall removes whatever cmdInstall set up.
func cmdUninstall(args []string) error {
	return uninstallService()
}

// resolveExecutable returns the real, symlink-resolved path to the running
// binary, so the installed auto-start entry keeps working even if the
// process was launched via a symlink (e.g. some package managers, `go
// install`).
func resolveExecutable() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("resolve own executable path: %w", err)
	}
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		exe = resolved
	}
	return exe, nil
}
