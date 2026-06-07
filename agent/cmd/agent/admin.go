package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"text/tabwriter"
	"time"

	"github.com/skip2/go-qrcode"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/pairing"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/security"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

// runAdmin dispatches an admin subcommand. Each command operates on the agent's
// data dir (DB + cert) directly, so it works whether or not the daemon is up.
func runAdmin(cmd string, args []string) error {
	switch cmd {
	case "pair":
		return cmdPair(args)
	case "devices":
		return cmdDevices(args)
	case "revoke":
		return cmdRevokeOrRemove(args, false)
	case "remove":
		return cmdRevokeOrRemove(args, true)
	case "status":
		return cmdStatus(args)
	case "help", "-h", "--help":
		printAdminUsage(os.Stdout)
		return nil
	default:
		printAdminUsage(os.Stderr)
		return fmt.Errorf("unknown command %q", cmd)
	}
}

func printAdminUsage(w *os.File) {
	fmt.Fprint(w, `rfe-agent — Remote File Explorer host agent

Usage:
  rfe-agent [serve] [flags]      run the host daemon (default)
  rfe-agent pair [-ttl 1h]       mint a pairing code + QR for a new phone
  rfe-agent devices              list paired devices
  rfe-agent revoke <id>          block a device (accepts a unique id prefix)
  rfe-agent remove <id>          permanently delete a device
  rfe-agent status               show name, addresses, fingerprint, devices

Common flags: -data <dir> (or $RFE_DATA_DIR; default ~/.rfe-agent)
`)
}

// adminDataDir resolves the data dir: -data flag > $RFE_DATA_DIR > ~/.rfe-agent
// (matching the deployed systemd service).
func adminDataDir(flagVal string) string {
	if flagVal != "" {
		return flagVal
	}
	if env := os.Getenv("RFE_DATA_DIR"); env != "" {
		return env
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ".rfe-agent"
	}
	return filepath.Join(home, ".rfe-agent")
}

func openAdminStore(dataDir string) (*store.DB, error) {
	if _, err := os.Stat(dataDir); err != nil {
		return nil, fmt.Errorf("data dir %q not found (is the agent set up? use -data)", dataDir)
	}
	return store.Open(dataDir)
}

// cmdPair mints a single-use pairing code and prints it with a scannable QR.
func cmdPair(args []string) error {
	fs := flag.NewFlagSet("pair", flag.ExitOnError)
	data := fs.String("data", "", "agent data dir")
	addr := fs.String("addr", ":8765", "listen address the phone will dial (for the QR)")
	ttl := fs.Duration("ttl", pairing.DefaultTTL, "how long the code stays valid")
	_ = fs.Parse(args)

	dir := adminDataDir(*data)
	cert, err := security.LoadOrCreateCert(dir)
	if err != nil {
		return fmt.Errorf("cert: %w", err)
	}
	fingerprint := security.Fingerprint(cert)
	lan, ts := reachableAddresses(*addr)

	db, err := openAdminStore(dir)
	if err != nil {
		return err
	}
	defer db.Close()

	pm := pairing.New(db, lan, ts, fingerprint)
	code, payload, err := pm.Mint(*ttl)
	if err != nil {
		return fmt.Errorf("mint: %w", err)
	}

	fmt.Printf("Pairing code: %s   (expires in %s)\n", code, *ttl)
	fmt.Printf("LAN:          %s\n", orNone(lan))
	fmt.Printf("Tailscale:    %s\n", orNone(ts))
	fmt.Println()

	qr, err := qrcode.New(payload.JSON(), qrcode.Medium)
	if err == nil {
		fmt.Println(qr.ToSmallString(false))
	}
	fmt.Println("Scan in the app: Add computer → Scan QR.")
	return nil
}

// cmdDevices lists paired devices as a table.
func cmdDevices(args []string) error {
	fs := flag.NewFlagSet("devices", flag.ExitOnError)
	data := fs.String("data", "", "agent data dir")
	_ = fs.Parse(args)

	db, err := openAdminStore(adminDataDir(*data))
	if err != nil {
		return err
	}
	defer db.Close()

	devices, err := db.ListDevices()
	if err != nil {
		return err
	}
	if len(devices) == 0 {
		fmt.Println("No paired devices. Run `rfe-agent pair` to add one.")
		return nil
	}

	tw := tabwriter.NewWriter(os.Stdout, 0, 2, 2, ' ', 0)
	fmt.Fprintln(tw, "ID\tLABEL\tSTATUS\tLAST SEEN")
	for _, d := range devices {
		status := "active"
		if d.Revoked {
			status = "revoked"
		}
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\n",
			shortID(d.ID), d.Label, status, humanizeSince(d.LastSeen))
	}
	return tw.Flush()
}

// cmdRevokeOrRemove revokes (remove=false) or permanently deletes (remove=true)
// the device whose id (or unique id prefix) is given.
func cmdRevokeOrRemove(args []string, remove bool) error {
	fs := flag.NewFlagSet("revoke", flag.ExitOnError)
	data := fs.String("data", "", "agent data dir")
	_ = fs.Parse(args)

	if fs.NArg() < 1 {
		return fmt.Errorf("usage: rfe-agent %s <device-id>", verb(remove))
	}

	db, err := openAdminStore(adminDataDir(*data))
	if err != nil {
		return err
	}
	defer db.Close()

	id, err := db.ResolveDeviceID(fs.Arg(0))
	if err != nil {
		return err
	}
	label := deviceLabel(db, id)

	if remove {
		if err := db.DeleteDevice(id); err != nil {
			return err
		}
		fmt.Printf("Removed %q (%s)\n", label, shortID(id))
	} else {
		if err := db.RevokeDevice(id); err != nil {
			return err
		}
		fmt.Printf("Revoked %q (%s)\n", label, shortID(id))
	}
	return nil
}

// cmdStatus prints a one-glance summary of the agent.
func cmdStatus(args []string) error {
	fs := flag.NewFlagSet("status", flag.ExitOnError)
	data := fs.String("data", "", "agent data dir")
	addr := fs.String("addr", ":8765", "listen address (for resolving reachable IPs)")
	_ = fs.Parse(args)

	dir := adminDataDir(*data)
	db, err := openAdminStore(dir)
	if err != nil {
		return err
	}
	defer db.Close()

	name, _ := db.GetConfig("agentName")
	if name == "" {
		name = hostName()
	}
	lan, ts := reachableAddresses(*addr)
	devices, _ := db.ListDevices()
	active := 0
	for _, d := range devices {
		if !d.Revoked {
			active++
		}
	}

	fingerprint := "(no cert yet)"
	if cert, err := security.LoadOrCreateCert(dir); err == nil {
		fingerprint = security.Fingerprint(cert)
	}

	fmt.Printf("name:        %s\n", name)
	fmt.Printf("version:     %s\n", version)
	fmt.Printf("LAN:         %s\n", orNone(lan))
	fmt.Printf("Tailscale:   %s\n", orNone(ts))
	fmt.Printf("fingerprint: %s\n", fingerprint)
	fmt.Printf("devices:     %d active, %d total\n", active, len(devices))
	return nil
}

// --- helpers ---

func verb(remove bool) string {
	if remove {
		return "remove"
	}
	return "revoke"
}

func shortID(id string) string {
	if len(id) > 8 {
		return id[:8]
	}
	return id
}

func deviceLabel(db *store.DB, id string) string {
	devices, err := db.ListDevices()
	if err != nil {
		return "device"
	}
	for _, d := range devices {
		if d.ID == id {
			return d.Label
		}
	}
	return "device"
}

// humanizeSince renders a coarse relative time like "2m ago" / "3h ago".
func humanizeSince(t time.Time) string {
	d := time.Since(t)
	switch {
	case d < time.Minute:
		return "just now"
	case d < time.Hour:
		return fmt.Sprintf("%dm ago", int(d.Minutes()))
	case d < 24*time.Hour:
		return fmt.Sprintf("%dh ago", int(d.Hours()))
	default:
		return fmt.Sprintf("%dd ago", int(d.Hours()/24))
	}
}
