//go:build linux

package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// linuxUnitName must match the service name agent_control_linux.go already
// shells out to via `systemctl --user restart`.
const linuxUnitName = "rfe-agent.service"

func installService(execPath string) error {
	unitExec, err := systemdExecArg(execPath)
	if err != nil {
		return err
	}
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
`, unitExec)
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

func startService() error {
	unitPath, err := linuxUnitPath()
	if err != nil {
		return err
	}
	if _, err := os.Stat(unitPath); err != nil {
		if os.IsNotExist(err) {
			return fmt.Errorf("agent is not installed; run `rfe-agent install` first")
		}
		return fmt.Errorf("check user service: %w", err)
	}
	if err := runSystemctl("start", linuxUnitName); err != nil {
		return fmt.Errorf("start user service: %w", err)
	}
	fmt.Printf("Started %s\n", linuxUnitName)
	return nil
}

func stopService() error {
	unitPath, err := linuxUnitPath()
	if err != nil {
		return err
	}
	if _, err := os.Stat(unitPath); err != nil {
		if os.IsNotExist(err) {
			return fmt.Errorf("agent is not installed; run `rfe-agent install` first")
		}
		return fmt.Errorf("check user service: %w", err)
	}
	if err := runSystemctl("stop", linuxUnitName); err != nil {
		return fmt.Errorf("stop user service: %w", err)
	}
	fmt.Printf("Stopped %s; it remains enabled for the next login\n", linuxUnitName)
	return nil
}

func serviceStatus() (string, error) {
	unitPath, err := linuxUnitPath()
	if err != nil {
		return "", err
	}
	if _, err := os.Stat(unitPath); err != nil {
		if os.IsNotExist(err) {
			return "not installed", nil
		}
		return "", fmt.Errorf("check user service file: %w", err)
	}
	active := runSystemctlOutput("is-active", linuxUnitName)
	enabled := runSystemctlOutput("is-enabled", linuxUnitName)
	return fmt.Sprintf("installed; %s; %s", strings.TrimSpace(enabled), strings.TrimSpace(active)), nil
}

func runSystemctlOutput(args ...string) string {
	cmd := exec.Command("systemctl", append([]string{"--user"}, args...)...)
	out, err := cmd.CombinedOutput()
	status := strings.TrimSpace(string(out))
	if status == "" && err != nil {
		return "unavailable (systemd --user did not respond)"
	}
	if status == "" {
		return "unknown"
	}
	return status
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

func linuxUnitPath() (string, error) {
	dir, err := userSystemdUnitDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, linuxUnitName), nil
}

func systemdExecArg(value string) (string, error) {
	if strings.ContainsAny(value, "\r\n") {
		return "", fmt.Errorf("agent executable path contains a line break and cannot be installed")
	}
	escaped := strings.NewReplacer("\\", "\\\\", `"`, `\"`, "%", "%%").Replace(value)
	return `"` + escaped + `"`, nil
}

func userSystemdUnitDir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home dir: %w", err)
	}
	return filepath.Join(home, ".config", "systemd", "user"), nil
}
