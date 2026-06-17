package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/skip2/go-qrcode"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/pairing"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/security"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/server"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/settings"
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
	case "jail":
		return cmdJail(args)
	case "readonly":
		return cmdReadonly(args)
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
  rfe-agent jail <id> <path>     confine a device to <path> (empty "" clears it)
  rfe-agent readonly <id> <on|off>  allow browse/download but block all writes
  rfe-agent status               show name, addresses, fingerprint, devices

Common flags: -data <dir> (or $RFE_DATA_DIR; default ~/.rfe-agent)
`)
}

// adminDataDir resolves the data dir: -data flag > $RFE_DATA_DIR > ~/.rfe-agent.
// Delegates to defaultDataDir (main.go) so the admin CLI and the daemon always
// agree on which DB to open by default.
func adminDataDir(flagVal string) string {
	if flagVal != "" {
		return flagVal
	}
	return defaultDataDir()
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
	lan, ts, _ := reachableAddresses(*addr)

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
	fmt.Fprintln(tw, "ID\tLABEL\tSTATUS\tACCESS\tLAST SEEN")
	for _, d := range devices {
		status := "active"
		if d.Revoked {
			status = "revoked"
		}
		access := "read-write"
		if d.ReadOnly {
			access = "read-only"
		}
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\t%s\n",
			shortID(d.ID), d.Label, status, access, humanizeSince(d.LastSeen))
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

// cmdJail sets (or clears) a device's per-device path jail (H2). This used to
// be reachable via PATCH /v1/devices/{id} from the app; that route now
// returns 403 for all app callers (device access limits are a PC-side
// concern), so this CLI command is the only way to configure it.
//
// Pass an empty string ("") as <path> to clear a device's per-device jail
// (it then falls back to the agent's configured global roots, as before).
// A non-empty <path> must be an absolute path that resolves within the
// agent's configured global roots — the same containment rule the daemon
// enforces, via server.ValidateJailRoot/server.SetDeviceJail.
func cmdJail(args []string) error {
	fs := flag.NewFlagSet("jail", flag.ExitOnError)
	data := fs.String("data", "", "agent data dir")
	_ = fs.Parse(args)

	if fs.NArg() < 2 {
		return fmt.Errorf("usage: rfe-agent jail <device-id> <path>  (pass \"\" for <path> to clear)")
	}

	dir := adminDataDir(*data)
	db, err := openAdminStore(dir)
	if err != nil {
		return err
	}
	defer db.Close()

	id, err := db.ResolveDeviceID(fs.Arg(0))
	if err != nil {
		return err
	}
	label := deviceLabel(db, id)

	// Load the agent's configured global roots the same way the daemon
	// does (settings.Load reads the persisted "roots" config key once it
	// exists; passing nil seed roots here is a no-op against an existing
	// DB — it only seeds on a brand-new store, which the daemon's first
	// run would already have done).
	st, err := settings.Load(db, false, nil, "")
	if err != nil {
		return fmt.Errorf("settings: %w", err)
	}

	jailRoot := fs.Arg(1)
	clean, err := server.SetDeviceJail(db, id, jailRoot, st.Roots(), st.IsReadOnly())
	if err != nil {
		return err
	}

	if clean == "" {
		fmt.Printf("Cleared jail for %q (%s)\n", label, shortID(id))
	} else {
		fmt.Printf("Jailed %q (%s) to %s\n", label, shortID(id), clean)
	}
	return nil
}

// cmdReadonly sets or clears a device's per-device read-only flag (#8). Like
// jail, this is a PC-side concern with no app-facing route. A read-only device
// can browse and download but every filesystem write is rejected.
func cmdReadonly(args []string) error {
	fs := flag.NewFlagSet("readonly", flag.ExitOnError)
	data := fs.String("data", "", "agent data dir")
	_ = fs.Parse(args)

	if fs.NArg() < 2 {
		return fmt.Errorf("usage: rfe-agent readonly <device-id> <on|off>")
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
	ro, err := parseOnOff(fs.Arg(1))
	if err != nil {
		return err
	}
	if err := db.SetDeviceReadOnly(id, ro); err != nil {
		return err
	}
	label := deviceLabel(db, id)
	if ro {
		fmt.Printf("Set %q (%s) to read-only\n", label, shortID(id))
	} else {
		fmt.Printf("Set %q (%s) to read-write\n", label, shortID(id))
	}
	return nil
}

// parseOnOff accepts on/off (and true/false, 1/0, yes/no, case-insensitive).
func parseOnOff(s string) (bool, error) {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "on", "true", "1", "yes":
		return true, nil
	case "off", "false", "0", "no":
		return false, nil
	default:
		return false, fmt.Errorf("invalid value %q: use on or off", s)
	}
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
	lan, ts, _ := reachableAddresses(*addr)
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
