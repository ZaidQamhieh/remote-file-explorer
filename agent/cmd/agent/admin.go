package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/skip2/go-qrcode"
	"golang.org/x/term"

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
	case "allow":
		return cmdAllow(args)
	case "backup-dir":
		return cmdBackupDir(args)
	case "status":
		return cmdStatus(args)
	case "audit":
		return cmdAudit(args)
	case "adduser":
		return cmdAddUser(args)
	case "install":
		return cmdInstall(args)
	case "setup":
		return cmdSetup(args)
	case "uninstall":
		return cmdUninstall(args)
	case "start":
		return cmdStart(args)
	case "stop":
		return cmdStop(args)
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
  rfe-agent pair requests        list phones waiting for approval (match codes)
  rfe-agent pair accept|reject [id]   answer a waiting phone
  rfe-agent devices              list paired devices
  rfe-agent revoke <id>          block a device (accepts a unique id prefix)
  rfe-agent remove <id>          permanently delete a device
  rfe-agent jail <id> <path>     confine a device to <path> (empty "" clears it)
  rfe-agent allow <id> <list>    set what a device may do: any of browse,download,upload,
                                  modify,delete,share, or all / none (replaces its grants)
  rfe-agent backup-dir [<path>|none]  show or set the folder phone photo backups go to
                                  (must be inside an allowed folder; restart the agent to apply)
  rfe-agent readonly <id> <on|off>  allow browse/download but block all writes
  rfe-agent status               show name, addresses, fingerprint, devices
  rfe-agent audit [-n 50]        show the account/device/share audit trail
  rfe-agent adduser <username>   create the account used to log in from the
                                  phone app / web companion (prompts for a
                                  password, hidden input). Alternatively, use
                                  the Register tab in the app/web companion
                                  with a code from "rfe-agent pair" to do
                                  this without the terminal.
  rfe-agent install              set up per-user auto-start at login
                                  (systemd --user unit on Linux, launchd
                                  LaunchAgent on macOS, Scheduled Task on
                                  Windows — no root/admin required)
  rfe-agent setup [-root <path>] first-run setup: restrict access to a folder,
                                  install the per-user service, and print a
                                  one-time pairing QR (defaults to your home)
  rfe-agent start                start the installed per-user agent
  rfe-agent stop                 stop it until you start it or next login
  rfe-agent uninstall            stop and remove the auto-start entry

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
	if len(args) > 0 {
		switch args[0] {
		case "requests":
			return cmdPairRequests(args[1:])
		case "accept":
			return cmdPairDecide(args[1:], true)
		case "reject":
			return cmdPairDecide(args[1:], false)
		}
	}
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
	fmt.Printf("Fingerprint:  %s\n", fingerprint)
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

// cmdPairRequests lists phones waiting for approval, with their match codes.
func cmdPairRequests(args []string) error {
	fs := flag.NewFlagSet("pair requests", flag.ExitOnError)
	data := fs.String("data", "", "agent data dir")
	_ = fs.Parse(args)
	dir := adminDataDir(*data)
	cert, err := security.LoadOrCreateCert(dir)
	if err != nil {
		return fmt.Errorf("cert: %w", err)
	}
	db, err := openAdminStore(dir)
	if err != nil {
		return err
	}
	defer db.Close()
	list, err := db.ListPendingPairRequests()
	if err != nil {
		return err
	}
	if len(list) == 0 {
		fmt.Println("No pairing requests waiting.")
		return nil
	}
	for _, r := range list {
		sas, _ := pairing.SAS(security.Fingerprint(cert), r.ClientNonce, r.ID)
		fmt.Printf("%s  %-24s  from %-15s  match code %s\n", r.ID[:8], r.Label, r.RemoteIP, sas)
		if d, ok, _ := db.ClientDeviceByID(r.ClientID); ok && (d.Revoked || (d.PublicKey != "" && d.PublicKey != r.PublicKey)) {
			fmt.Printf("          replaces the paired device %q: new key and token, access reset to browse only\n", d.Label)
		}
	}
	fmt.Println("Approve with `rfe-agent pair accept <id>` only if the code matches the one on the phone.")
	return nil
}

// cmdPairDecide approves or rejects a waiting request by (a prefix of) its id.
// With no id it answers the only waiting request.
func cmdPairDecide(args []string, approve bool) error {
	fs := flag.NewFlagSet("pair accept", flag.ExitOnError)
	data := fs.String("data", "", "agent data dir")
	_ = fs.Parse(args)
	db, err := openAdminStore(adminDataDir(*data))
	if err != nil {
		return err
	}
	defer db.Close()
	list, err := db.ListPendingPairRequests()
	if err != nil {
		return err
	}
	var match []string
	for _, r := range list {
		if fs.NArg() == 0 || strings.HasPrefix(r.ID, fs.Arg(0)) {
			match = append(match, r.ID)
		}
	}
	if len(match) != 1 {
		return fmt.Errorf("%d waiting requests match; give the id from `rfe-agent pair requests`", len(match))
	}
	if err := db.DecidePairRequest(match[0], approve); err != nil {
		return err
	}
	if approve {
		fmt.Println("Approved. The phone finishes pairing within a couple of seconds.")
	} else {
		fmt.Println("Rejected.")
	}
	return nil
}

// cmdAddUser creates the account used by POST /v1/login (an additional way
// to obtain a device token, alongside the one-time pairing code above — not
// a replacement for it). Fails if the username already exists rather than
// silently overwriting its password.
func cmdAddUser(args []string) error {
	fs := flag.NewFlagSet("adduser", flag.ExitOnError)
	data := fs.String("data", "", "agent data dir")
	passwordFlag := fs.String("password", "", "password (non-interactive; omit to be prompted with hidden input)")
	_ = fs.Parse(args)

	if fs.NArg() < 1 {
		return fmt.Errorf("usage: rfe-agent adduser <username> [-password <pw>] [-data <dir>]")
	}
	username := fs.Arg(0)

	password := *passwordFlag
	if password == "" {
		fmt.Print("Password: ")
		passwordBytes, err := term.ReadPassword(int(os.Stdin.Fd()))
		fmt.Println()
		if err != nil {
			return fmt.Errorf("read password: %w", err)
		}
		password = strings.TrimSpace(string(passwordBytes))
	}
	if len(password) < 8 {
		return fmt.Errorf("password must be at least 8 characters")
	}

	hash, err := security.HashPassword(password)
	if err != nil {
		return fmt.Errorf("hash password: %w", err)
	}

	db, err := openAdminStore(adminDataDir(*data))
	if err != nil {
		return err
	}
	defer db.Close()

	if err := db.CreateUser(username, hash); err != nil {
		return fmt.Errorf("create user %q (does it already exist?): %w", username, err)
	}
	fmt.Printf("Account %q created — log in from the phone app or web companion with this username and password.\n", username)
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

// cmdAudit prints the audit trail newest-first — the PC-side counterpart of
// GET /v1/audit, so the host owner can read it without a paired device.
func cmdAudit(args []string) error {
	fs := flag.NewFlagSet("audit", flag.ExitOnError)
	data := fs.String("data", "", "agent data dir")
	n := fs.Int("n", 50, "number of entries to show")
	_ = fs.Parse(args)

	db, err := openAdminStore(adminDataDir(*data))
	if err != nil {
		return err
	}
	defer db.Close()

	entries, err := db.AuditEntries(*n, 0)
	if err != nil {
		return err
	}
	if len(entries) == 0 {
		fmt.Println("No audit entries yet.")
		return nil
	}

	tw := tabwriter.NewWriter(os.Stdout, 0, 2, 2, ' ', 0)
	fmt.Fprintln(tw, "WHEN\tACTION\tACTOR\tTARGET\tDETAIL")
	for _, e := range entries {
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\t%s\n",
			e.At.Format("2006-01-02 15:04"), e.Action, e.Actor, e.Target, e.Detail)
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
	service, err := serviceStatus()
	if err != nil {
		return fmt.Errorf("read local service status: %w", err)
	}
	fmt.Printf("service:     %s\n", service)
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

// parseAllow turns "download,upload" (or "all" / "none") into the six file grants.
func parseAllow(list string) (grants [6]bool, err error) {
	names := []string{"browse", "download", "upload", "modify", "delete", "share"}
	switch strings.ToLower(strings.TrimSpace(list)) {
	case "all":
		return [6]bool{true, true, true, true, true, true}, nil
	case "none", "":
		return grants, nil
	}
	for _, part := range strings.Split(list, ",") {
		part = strings.ToLower(strings.TrimSpace(part))
		found := false
		for i, n := range names {
			if n == part {
				grants[i], found = true, true
			}
		}
		if !found {
			return grants, fmt.Errorf("unknown permission %q (use %s, all or none)", part, strings.Join(names, ", "))
		}
	}
	return grants, nil
}

// cmdAllow replaces a device's file permissions.
func cmdAllow(args []string) error {
	fs := flag.NewFlagSet("allow", flag.ExitOnError)
	data := fs.String("data", "", "agent data dir")
	_ = fs.Parse(args)
	if fs.NArg() < 2 {
		return fmt.Errorf("usage: rfe-agent allow <device-id> <browse,download,upload,modify,delete,share|all|none>")
	}
	g, err := parseAllow(fs.Arg(1))
	if err != nil {
		return err
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
	if err := db.SetDeviceFilePermissions(id, g[0], g[1], g[2], g[3], g[4], g[5]); err != nil {
		return err
	}
	fmt.Printf("Set %q (%s) permissions to %s\n", deviceLabel(db, id), shortID(id), fs.Arg(1))
	return nil
}

// backupDirInRoots reports whether dir is one of the allowed roots or inside one (no roots means unrestricted).
func backupDirInRoots(dir string, roots []string) bool {
	if len(roots) == 0 {
		return true
	}
	for _, r := range roots {
		rel, err := filepath.Rel(filepath.Clean(r), dir)
		if err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			return true
		}
	}
	return false
}

// cmdBackupDir shows or sets the destination folder for phone photo backup.
func cmdBackupDir(args []string) error {
	fs := flag.NewFlagSet("backup-dir", flag.ExitOnError)
	data := fs.String("data", "", "agent data dir")
	_ = fs.Parse(args)
	db, err := openAdminStore(adminDataDir(*data))
	if err != nil {
		return err
	}
	defer db.Close()
	if fs.NArg() == 0 {
		cur, _ := db.GetConfig("photoBackupRoot")
		fmt.Println("photo backup folder:", orNone(cur))
		return nil
	}
	arg := strings.TrimSpace(fs.Arg(0))
	if arg == "none" || arg == "" {
		if err := db.SetConfig("photoBackupRoot", ""); err != nil {
			return err
		}
		fmt.Println("Photo backup folder cleared. Restart the agent to apply.")
		return nil
	}
	dir, err := filepath.Abs(arg)
	if err != nil {
		return err
	}
	rootsCSV, _ := db.GetConfig("roots")
	var roots []string
	for _, r := range strings.Split(rootsCSV, "\n") {
		if r = strings.TrimSpace(r); r != "" {
			roots = append(roots, r)
		}
	}
	if !backupDirInRoots(dir, roots) {
		return fmt.Errorf("%s is outside the folders this agent shares (%s); phones could not write there", dir, strings.Join(roots, ", "))
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	if err := db.SetConfig("photoBackupRoot", dir); err != nil {
		return err
	}
	fmt.Println("Photo backup folder set to", dir, "— restart the agent to apply.")
	return nil
}
