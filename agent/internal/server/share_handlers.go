// Package server — R1 one-time share link handlers.
//
// GET /v1/share/{token} is the only unauthenticated route in the agent
// besides /health and /pair — see docs/r1-share-link-threat-model.md. Every
// other route in this file is authenticated and mounted in server.go's
// authenticated route group.
package server

import (
	"crypto/sha256"
	"encoding/hex"
	"net"
	"net/http"
	"os"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

const (
	shareDefaultExpiry = 15 * time.Minute
	shareMaxExpiry     = 24 * time.Hour
	shareMaxFileBytes  = 500 << 20

	// T2: the token is 32 bytes of crypto/rand (2^256 space) so brute force is
	// already infeasible, but the unauthenticated /share/{token} route is
	// rate-limited anyway, matching /pair's defense-in-depth posture.
	shareRateLimitAttempts = 10
	shareRateLimitWindow   = time.Minute

	// shareSweepInterval is how often StartShareSweeper deletes expired
	// share tokens (T6).
	shareSweepInterval = 5 * time.Minute
)

func hashShareToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// --------- POST /v1/share/mint (authenticated) ---------

type mintShareRequest struct {
	Path             string `json:"path"`
	ExpiresInSeconds int64  `json:"expiresInSeconds"`
}

type mintShareResponse struct {
	Token     string `json:"token"`
	TokenHash string `json:"tokenHash"`
	ExpiresAt int64  `json:"expiresAt"`
	URL       string `json:"url"`
}

func mintShareHandler(cfg Config, db *store.DB, ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !cfg.Settings.IsAllowSharing() {
			writeError(w, http.StatusForbidden, "FORBIDDEN", "share links are disabled on this agent")
			return
		}

		var req mintShareRequest
		if !decodeJSONBody(w, r, &req) {
			return
		}
		if req.Path == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "path required")
			return
		}
		if req.ExpiresInSeconds < 0 || time.Duration(req.ExpiresInSeconds)*time.Second > shareMaxExpiry {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "expiresInSeconds exceeds the 24h maximum")
			return
		}

		reqOps := opsFromContext(r.Context(), ops)
		resolved, err := reqOps.Resolve(req.Path)
		if err != nil {
			handleFsError(w, err)
			return
		}
		info, err := os.Stat(resolved)
		if err != nil {
			if os.IsNotExist(err) {
				writeError(w, http.StatusNotFound, "NOT_FOUND", "file not found")
			} else {
				writeInternalError(w, r, err)
			}
			return
		}
		if !info.Mode().IsRegular() {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "only regular files can be shared")
			return
		}
		if info.Size() > shareMaxFileBytes {
			writeError(w, http.StatusRequestEntityTooLarge, "PAYLOAD_TOO_LARGE", "shared files cannot exceed 500 MiB")
			return
		}

		expiresIn := shareDefaultExpiry
		if req.ExpiresInSeconds > 0 {
			expiresIn = time.Duration(req.ExpiresInSeconds) * time.Second
		}
		expiresAt := time.Now().Add(expiresIn)

		token, err := randomToken(32)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", "failed to generate token")
			return
		}
		hash := hashShareToken(token)

		if err := db.CreateShareToken(hash, resolved, expiresAt); err != nil {
			writeInternalError(w, r, err)
			return
		}
		_ = db.LogShareMint(hash, resolved, expiresAt)

		writeJSON(w, http.StatusOK, mintShareResponse{
			Token:     token,
			TokenHash: hash,
			ExpiresAt: expiresAt.Unix(),
			URL:       shareURL(cfg, token),
		})
	}
}

// shareURL builds the fully-qualified share link for token, preferring the
// Tailscale address (reachable from anywhere) over the LAN address.
func shareURL(cfg Config, token string) string {
	addr := cfg.Address
	if cfg.TailscaleAddress != "" {
		addr = cfg.TailscaleAddress
	}
	return "https://" + addr + "/v1/share/" + token
}

// --------- GET /v1/share/{token} (UNAUTHENTICATED — see package doc) ---------

func serveShareHandler(db *store.DB, ops *fsops.Ops) http.HandlerFunc {
	limiter := newFixedWindowLimiter(shareRateLimitAttempts, shareRateLimitWindow)
	return func(w http.ResponseWriter, r *http.Request) {
		if !limiter.AllowRequest(r) {
			w.Header().Set("Retry-After", "60")
			writeError(w, http.StatusTooManyRequests, "RATE_LIMITED", "too many share requests, try again later")
			return
		}

		token := chi.URLParam(r, "token")
		hash := hashShareToken(token)

		path, ok, err := db.LookupShareToken(hash)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		if !ok {
			// Don't distinguish "expired" from "never existed" (T1/T6).
			writeError(w, http.StatusNotFound, "NOT_FOUND", "share link not found or expired")
			return
		}

		// Defense in depth (T3): re-validate the minted path against the
		// agent's CURRENT jail config, in case roots changed since mint time.
		resolved, err := ops.Resolve(path)
		if err != nil {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "share link not found or expired")
			return
		}

		// The file may have been deleted/moved since mint (T6-adjacent).
		f, err := os.Open(resolved)
		if err != nil {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "share link not found or expired")
			return
		}
		defer f.Close()
		info, err := f.Stat()
		if err != nil || !info.Mode().IsRegular() || info.Size() > shareMaxFileBytes {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "share link not found or expired")
			return
		}

		consumedPath, consumed, err := db.ConsumeShareToken(hash)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		if !consumed || consumedPath != path {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "share link not found or expired")
			return
		}

		ip := r.RemoteAddr
		if host, _, splitErr := net.SplitHostPort(r.RemoteAddr); splitErr == nil {
			ip = host
		}
		_ = db.LogShareServed(hash, ip)

		http.ServeContent(w, r, info.Name(), info.ModTime(), f)
	}
}

// --------- DELETE /v1/share/{tokenHash} (authenticated) ---------

func revokeShareHandler(db *store.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !requireAdminDevice(w, r) {
			return
		}
		hash := chi.URLParam(r, "tokenHash")
		if hash == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "tokenHash required")
			return
		}
		if err := db.DeleteShareToken(hash); err != nil {
			writeInternalError(w, r, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// --------- GET /v1/share (authenticated) ---------

func listSharesHandler(db *store.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !requireAdminDevice(w, r) {
			return
		}
		tokens, err := db.ListShareTokens()
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		out := make([]map[string]any, 0, len(tokens))
		for _, t := range tokens {
			out = append(out, map[string]any{
				"tokenHash": t.TokenHash,
				"path":      t.Path,
				"expiresAt": t.Expires.Unix(),
			})
		}
		writeJSON(w, http.StatusOK, out)
	}
}

// StartShareSweeper launches a background goroutine that deletes expired
// share tokens every shareSweepInterval (T6). It never stops — the agent
// process owns its lifetime, same as the mDNS advertisement in main.go.
func StartShareSweeper(db *store.DB) {
	go func() {
		ticker := time.NewTicker(shareSweepInterval)
		defer ticker.Stop()
		for range ticker.C {
			_, _ = db.SweepExpiredShareTokens()
		}
	}()
}
