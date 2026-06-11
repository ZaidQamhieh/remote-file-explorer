// Command agent is the Remote File Explorer host service. It serves the file
// API to paired mobile devices over TLS, reachable on the LAN or via Tailscale.
//
// Invoked with no arguments (or a leading flag, or "serve") it runs the daemon.
// Other first arguments are admin subcommands — see admin.go (pair, devices,
// revoke, remove, status).
package main

import (
	"context"
	"crypto/tls"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/netinfo"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/pairing"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/security"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/server"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/settings"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/transfer"
)

const version = "1.0.0"

func main() {
	args := os.Args[1:]
	// Backward compatible: no args, a leading flag, or "serve" runs the daemon —
	// so the existing systemd unit (`rfe-agent -addr ... -name ...`) is unchanged.
	if len(args) == 0 || strings.HasPrefix(args[0], "-") || args[0] == "serve" {
		if len(args) > 0 && args[0] == "serve" {
			args = args[1:]
		}
		runServe(args)
		return
	}
	// Otherwise dispatch an admin subcommand (admin.go).
	if err := runAdmin(args[0], args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func runServe(args []string) {
	fs := flag.NewFlagSet("serve", flag.ExitOnError)
	addr := fs.String("addr", ":8765", "listen address (host:port)")
	name := fs.String("name", hostName(), "agent display name shown to the phone")
	dataDir := fs.String("data", defaultDataDir(), "directory for certs, db, and state (precedence: -data > $RFE_DATA_DIR > ~/.rfe-agent)")
	readOnly := fs.Bool("read-only", false, "reject all write operations")
	roots := fs.String("roots", "", "comma-separated allowed root paths (empty = allow all)")
	_ = fs.Parse(args)

	if err := os.MkdirAll(*dataDir, 0o700); err != nil {
		log.Fatalf("data dir: %v", err)
	}

	cert, err := security.LoadOrCreateCert(*dataDir)
	if err != nil {
		log.Fatalf("tls: %v", err)
	}
	fingerprint := security.Fingerprint(cert)
	log.Printf("agent %q  cert-fingerprint=%s", *name, fingerprint)

	lanAddr, tsAddr := reachableAddresses(*addr)
	log.Printf("reachable at  lan=%s  tailscale=%s", orNone(lanAddr), orNone(tsAddr))

	db, err := store.Open(*dataDir)
	if err != nil {
		log.Fatalf("store: %v", err)
	}
	defer db.Close()

	tempDir := filepath.Join(*dataDir, "transfers")
	tm, err := transfer.New(db, tempDir)
	if err != nil {
		log.Fatalf("transfer: %v", err)
	}

	thumbCacheDir := filepath.Join(*dataDir, "thumbs")
	if err := os.MkdirAll(thumbCacheDir, 0o700); err != nil {
		log.Fatalf("thumb cache dir: %v", err)
	}

	updatesDir := filepath.Join(*dataDir, "updates")
	if err := os.MkdirAll(updatesDir, 0o755); err != nil {
		log.Fatalf("updates dir: %v", err)
	}

	pm := pairing.New(db, lanAddr, tsAddr, fingerprint)
	log.Printf("run `rfe-agent pair` to add a device")

	// Parse seed roots from the flag (first-run only; DB wins thereafter).
	var seedRoots []string
	if *roots != "" {
		for _, r := range strings.Split(*roots, ",") {
			if r = strings.TrimSpace(r); r != "" {
				seedRoots = append(seedRoots, r)
			}
		}
	}

	st, err := settings.Load(db, *readOnly, seedRoots, *name)
	if err != nil {
		log.Fatalf("settings: %v", err)
	}

	handler, err := server.New(server.Config{
		Name:             st.AgentName(),
		Version:          version,
		CertFingerprint:  fingerprint,
		Address:          lanAddr,
		TailscaleAddress: tsAddr,
		ThumbCacheDir:    thumbCacheDir,
		Settings:         st,
		UpdatesDir:       updatesDir,
	}, db, pm, tm)
	if err != nil {
		log.Fatalf("server: %v", err)
	}

	srv := &http.Server{
		Addr:    *addr,
		Handler: handler,
		TLSConfig: &tls.Config{
			Certificates: []tls.Certificate{cert},
			MinVersion:   tls.VersionTLS12,
		},
		// Headers should arrive quickly regardless of payload size.
		ReadHeaderTimeout: 10 * time.Second,
		// Large file uploads/downloads stream through this server (chunked
		// transfers and /v1/content), so Read/Write timeouts must be generous
		// enough to cover slow links transferring big files. 30 minutes
		// comfortably covers a multi-GB transfer over a slow connection
		// without leaving truly-stuck connections open indefinitely.
		ReadTimeout:  30 * time.Minute,
		WriteTimeout: 30 * time.Minute,
		// IdleTimeout bounds how long a keep-alive connection can sit idle
		// between requests; 2 minutes is plenty for normal browsing/polling
		// while freeing resources from abandoned connections.
		IdleTimeout: 2 * time.Minute,
	}

	go func() {
		log.Printf("listening on https://%s/v1  (LAN + Tailscale)", *addr)
		// Cert/key are already in TLSConfig, so empty paths are correct here.
		if err := srv.ListenAndServeTLS("", ""); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("serve: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("shutdown: %v", err)
	}
	log.Println("agent stopped")
}

func hostName() string {
	h, err := os.Hostname()
	if err != nil {
		return "host-agent"
	}
	return h
}

// defaultDataDir returns the data directory used when -data is not given:
// $RFE_DATA_DIR if set, otherwise ~/.rfe-agent (matching the deployed systemd
// service and release.sh, which publish OTA updates to ~/.rfe-agent/updates/).
// Falls back to the OS config dir if the home directory can't be resolved.
//
// This is the single source of truth for the default data dir, shared by the
// daemon (runServe) and the admin CLI (adminDataDir in admin.go) so that
// `rfe-agent` and `rfe-agent devices`/`pair`/etc. always operate on the same
// database by default. Precedence: -data flag > $RFE_DATA_DIR > ~/.rfe-agent.
func defaultDataDir() string {
	if env := os.Getenv("RFE_DATA_DIR"); env != "" {
		return env
	}
	home, err := os.UserHomeDir()
	if err != nil {
		if dir, cfgErr := os.UserConfigDir(); cfgErr == nil {
			return filepath.Join(dir, "remote-file-explorer")
		}
		return ".rfe-agent"
	}
	return filepath.Join(home, ".rfe-agent")
}

// reachableAddresses turns the listen address into the concrete host:port
// pairs the phone can actually dial. If the user bound to a specific host
// (e.g. "192.168.1.5:8765") that's trusted as-is and treated as the LAN
// address; a wildcard bind ("0.0.0.0:8765", ":8765") is resolved to the
// machine's real LAN and Tailscale IPs via netinfo.
func reachableAddresses(listenAddr string) (lan, tailscale string) {
	host, port, err := net.SplitHostPort(listenAddr)
	if err != nil {
		return "", ""
	}
	if host != "" && host != "0.0.0.0" && host != "::" {
		return listenAddr, ""
	}
	lanIP, tsIP := netinfo.LocalAddresses()
	if lanIP != "" {
		lan = net.JoinHostPort(lanIP, port)
	}
	if tsIP != "" {
		tailscale = net.JoinHostPort(tsIP, port)
	}
	return lan, tailscale
}

func orNone(s string) string {
	if s == "" {
		return "(none detected)"
	}
	return s
}
