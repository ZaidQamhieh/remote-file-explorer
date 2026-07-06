//go:build windows

package main

import (
	"fmt"
	"os"
	"os/exec"
)

const scheduledTaskName = "RFEAgent"

// installService registers a per-user Scheduled Task that starts at logon.
// /rl limited keeps it a standard-user task (no admin elevation prompt),
// matching the no-root Linux/macOS install.
func installService(execPath string) error {
	cmd := exec.Command("schtasks", "/create", "/tn", scheduledTaskName,
		"/tr", execPath, "/sc", "onlogon", "/rl", "limited", "/f")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("schtasks create: %w", err)
	}

	// Start it now too rather than making the user log out/in to see it
	// running. Non-fatal: the task is installed either way.
	runCmd := exec.Command("schtasks", "/run", "/tn", scheduledTaskName)
	runCmd.Stdout = os.Stdout
	runCmd.Stderr = os.Stderr
	if err := runCmd.Run(); err != nil {
		fmt.Printf("Installed scheduled task %q, but couldn't start it now (%v) — it will start at next logon\n", scheduledTaskName, err)
		return nil
	}

	fmt.Printf("Installed and started scheduled task %q (runs at logon)\n", scheduledTaskName)
	return nil
}

func uninstallService() error {
	cmd := exec.Command("schtasks", "/delete", "/tn", scheduledTaskName, "/f")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("schtasks delete: %w", err)
	}

	fmt.Printf("Removed scheduled task %q\n", scheduledTaskName)
	return nil
}
