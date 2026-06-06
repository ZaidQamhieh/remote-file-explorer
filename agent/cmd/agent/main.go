// Command agent is the Remote File Explorer host service. It serves the file
// API to paired mobile devices over TLS, reachable on the LAN or via Tailscale.
package main

import (
	"context"
	"crypto/tls"
	"errors"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/security"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/server"
)

const version = "0.1.0"

func main() {
	addr := flag.String("addr", ":8765", "listen address (host:port)")
	name := flag.String("name", hostName(), "agent display name shown to the phone")
	dataDir := flag.String("data", defaultDataDir(), "directory for certs, db, and state")
	readOnly := flag.Bool("read-only", false, "reject all write operations")
	flag.Parse()

	cert, err := security.LoadOrCreateCert(*dataDir)
	if err != nil {
		log.Fatalf("tls: %v", err)
	}
	log.Printf("agent %q  cert-fingerprint=%s", *name, security.Fingerprint(cert))

	handler := server.New(server.Config{Name: *name, Version: version, ReadOnly: *readOnly})

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
