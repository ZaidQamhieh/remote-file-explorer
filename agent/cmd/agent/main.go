// Command agent is the Remote File Explorer host service. It serves the file
// API to paired mobile devices over TLS, reachable on the LAN or via Tailscale.
package main

import (
	"context"
	"crypto/tls"
	"errors"
	"flag"
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
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/transfer"
)

const version = "0.1.0"

func main() {
	addr := flag.String("addr", ":8765", "listen address (host:port)")
	name := flag.String("name", hostName(), "agent display name shown to the phone")
	dataDir := flag.String("data", defaultDataDir(), "directory for certs, db, and state")
	readOnly := flag.Bool("read-only", false, "reject all write operations")
	roots := flag.String("roots", "", "comma-separated allowed root paths (empty = allow all)")
	flag.Parse()

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

	pm, err := pairing.New(lanAddr, tsAddr, fingerprint)
	if err != nil {
		log.Fatalf("pairing: %v", err)
	}

	var allowedRoots []string
	if *roots != "" {
		for _, r := range strings.Split(*roots, ",") {
			r = strings.TrimSpace(r)
			if r != "" {
				allowedRoots = append(allowedRoots, r)
			}
		}
	}

	handler := server.New(server.Config{
		Name:             *name,
		Version:          version,
		ReadOnly:         *readOnly,
		CertFingerprint:  fingerprint,
		Address:          lanAddr,
		TailscaleAddress: tsAddr,
		AllowedRoots:     allowedRoots,
	}, db, pm, tm)

	srv := &http.Server{
		Addr:    *addr,
		Handler: handler,
		TLSConfig: &tls.Config{
			Certificates: []tls.Certificate{cert},
			MinVersion:   tls.VersionTLS12,
		},
		ReadHeaderTimeout: 10 * time.Second,
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

func defaultDataDir() string {
	dir, err := os.UserConfigDir()
	if err != nil {
		return ".rfe-agent"
	}
	return filepath.Join(dir, "remote-file-explorer")
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
