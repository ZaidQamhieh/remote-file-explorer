//go:build linux

package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// linuxUnitName must match the service name agent_control_linux.go already
// shells out to via `systemctl --user restart`.
const linuxUnitName = "rfe-agent.service"

func installService(execPath string) error {
	unitDir, err := userSystemdUnitDir()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(unitDir, 0o755); err != nil {
		return fmt.Errorf("create unit dir: %w", err)
	}

	unitPath := filepath.Join(unitDir, linuxUnitName)
	unit := fmt.Sprintf(`[Unit]
Description=Remote File Explorer agent

[Service]
ExecStart=%s
Restart=on-failure

[Install]
WantedBy=default.target
`, execPath)
	if err := os.WriteFile(unitPath, []byte(unit), 0o644); err != nil {
		return fmt.Errorf("write unit file: %w", err)
	}

	if err := runSystemctl("daemon-reload"); err != nil {
		return fmt.Errorf("systemctl daemon-reload: %w", err)
	}
	if err := runSystemctl("enable", "--now", linuxUnitName); err != nil {
		return fmt.Errorf("systemctl enable --now: %w", err)
	}

	fmt.Printf("Installed and started %s (unit: %s)\n", linuxUnitName, unitPath)
	return nil
}

func uninstallService() error {
	// Best-effort: disable/stop even if the unit was already gone, so a
	// half-installed state still cleans up.
	_ = runSystemctl("disable", "--now", linuxUnitName)

	unitDir, err := userSystemdUnitDir()
	if err != nil {
		return err
	}
	unitPath := filepath.Join(unitDir, linuxUnitName)
	if err := os.Remove(unitPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("remove unit file: %w", err)
	}

	fmt.Printf("Stopped and removed %s\n", linuxUnitName)
	return nil
}

func runSystemctl(args ...string) error {
	cmd := exec.Command("systemctl", append([]string{"--user"}, args...)...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func userSystemdUnitDir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home dir: %w", err)
	}
	return filepath.Join(home, ".config", "systemd", "user"), nil
}
