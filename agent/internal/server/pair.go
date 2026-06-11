// Package server — pair handler.
package server

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"time"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/pairing"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

// pairRateLimit caps unauthenticated /v1/pair attempts. The pairing code is
// only ~40 bits, so without throttling it's brute-forceable; 10/min is ample
// for legitimate use (a human typing/scanning a code) on a single-user agent.
const (
	pairRateLimitAttempts = 10
	pairRateLimitWindow   = time.Minute
)

type pairRequest struct {
	PairingCode     string `json:"pairingCode"`
	DeviceLabel     string `json:"deviceLabel"`
	ClientPublicKey string `json:"clientPublicKey"`
	// DeviceID is a hardware-stable client identifier (Android ID). When
	// present it deduplicates pairings so the same phone reuses its device row.
	DeviceID string `json:"deviceId"`
}

type pairResponse struct {
	DeviceToken      string `json:"deviceToken"`
	DeviceID         string `json:"deviceId"`
	AgentName        string `json:"agentName"`
	CertFingerprint  string `json:"certFingerprint"`
	Address          string `json:"address"`
	TailscaleAddress string `json:"tailscaleAddress,omitempty"`
}

func pairHandler(cfg Config, db *store.DB, pm *pairing.Manager) http.HandlerFunc {
	limiter := newFixedWindowLimiter(pairRateLimitAttempts, pairRateLimitWindow)
	return func(w http.ResponseWriter, r *http.Request) {
		if !limiter.Allow() {
			writeError(w, http.StatusTooManyRequests, "RATE_LIMITED", "too many pairing attempts, try again later")
			return
		}
		var req pairRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
			return
		}
		if !pm.Consume(req.PairingCode) {
			writeError(w, http.StatusUnauthorized, "INVALID_CODE", "invalid or expired pairing code")
			return
		}
		if req.DeviceLabel == "" {
			req.DeviceLabel = "unnamed-device"
		}

		token, err := randomToken(32)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", "failed to generate token")
			return
		}

		deviceID, err := db.UpsertDevice(req.DeviceID, req.DeviceLabel, token)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}

		writeJSON(w, http.StatusOK, pairResponse{
			DeviceToken:      token,
			DeviceID:         deviceID,
			AgentName:        cfg.Name,
			CertFingerprint:  cfg.CertFingerprint,
			Address:          cfg.Address,
			TailscaleAddress: cfg.TailscaleAddress,
		})
	}
}

func randomToken(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
