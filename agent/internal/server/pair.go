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
	PairingCode string `json:"pairingCode"`
	DeviceLabel string `json:"deviceLabel"`
	// DeviceID is a hardware-stable client identifier (Android ID). When
	// present it deduplicates pairings so the same phone reuses its device row.
	DeviceID string `json:"deviceId"`
	// DevicePublicKey is the device's permanent Ed25519 identity key
	// (standard base64), Nonce a value freshly minted by POST /v1/auth/challenge,
	// and Signature that nonce signed with the matching private key — proof of
	// possession, pinned to the device row on success. See device_identity.go.
	DevicePublicKey string `json:"devicePublicKey"`
	Nonce           string `json:"nonce"`
	Signature       string `json:"signature"`
}

type pairResponse struct {
	DeviceToken      string `json:"deviceToken"`
	DeviceID         string `json:"deviceId"`
	AgentName        string `json:"agentName"`
	CertFingerprint  string `json:"certFingerprint"`
	Address          string `json:"address"`
	TailscaleAddress string `json:"tailscaleAddress,omitempty"`
}

func pairHandler(cfg Config, db *store.DB, pm *pairing.Manager, nonces *nonceStore) http.HandlerFunc {
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
		// Validate device-identity proof BEFORE consuming the one-time
		// pairing code: the code is precious (minted at the terminal,
		// single-use) while a bad/expired nonce or signature is a
		// recoverable client-side hiccup — burning the code on that would
		// force a trip back to the PC for something that wasn't the code's
		// fault.
		if err := verifyDeviceProof(db, nonces, req.DeviceID, req.DevicePublicKey, req.Nonce, req.Signature, w, rePinOnKeyChange); err != nil {
			return // verifyDeviceProof already wrote the error response
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

		deviceID, err := db.UpsertDevice(req.DeviceID, req.DeviceLabel, token, req.DevicePublicKey, false)
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

// generatePairingHandler implements POST /v1/pairing/generate: mints a new
// one-time pairing code from an authenticated session, so a new device can be
// paired without a trip to the PC terminal (`rfe-agent pair`). Admin-only
// (see isAdminDevice) — an ordinary paired device (e.g. the phone app)
// minting fresh codes for arbitrary new devices is a materially bigger
// privilege than the read-only web-companion endpoints, so it is gated the
// same as managing other devices.
func generatePairingHandler(pm *pairing.Manager) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !isAdminDevice(deviceFromContext(r)) {
			writeError(w, http.StatusForbidden, "FORBIDDEN", "minting pairing codes requires an admin (login) session or the PC")
			return
		}
		var req struct {
			TTLSeconds int `json:"ttlSeconds"`
		}
		_ = json.NewDecoder(r.Body).Decode(&req) // body is optional; default TTL below
		ttl := pairing.DefaultTTL
		if req.TTLSeconds > 0 {
			ttl = time.Duration(req.TTLSeconds) * time.Second
		}
		code, payload, err := pm.Mint(ttl)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"pairingCode":      code,
			"expiresInSeconds": int(ttl.Seconds()),
			"qrPayload":        payload,
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
