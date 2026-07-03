// Package server — account registration.
//
// Unlike login, register is reachable with no account yet — so it needs its
// own gate against a stranger on the network creating an account (and thus a
// device token) before the owner does. It reuses the same one-time pairing
// code /v1/pair already requires (minted locally via `rfe-agent pair`,
// physical/terminal access to the host): register both creates the account
// and pairs the calling device in one step, letting first-time setup happen
// entirely from the phone app or web companion instead of also needing
// `rfe-agent adduser` at the terminal. adduser remains for headless setups.
package server

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/pairing"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/security"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

const (
	registerRateLimitAttempts = 10
	registerRateLimitWindow   = time.Minute
)

type registerRequest struct {
	PairingCode string `json:"pairingCode"`
	Username    string `json:"username"`
	Password    string `json:"password"`
	DeviceLabel string `json:"deviceLabel"`
	DeviceID    string `json:"deviceId"`
	// DevicePublicKey/Nonce/Signature — same device-identity proof as
	// pairRequest/loginRequest (see device_identity.go).
	DevicePublicKey string `json:"devicePublicKey"`
	Nonce           string `json:"nonce"`
	Signature       string `json:"signature"`
}

func registerHandler(cfg Config, db *store.DB, pm *pairing.Manager, nonces *nonceStore) http.HandlerFunc {
	limiter := newFixedWindowLimiter(registerRateLimitAttempts, registerRateLimitWindow)
	return func(w http.ResponseWriter, r *http.Request) {
		if !limiter.Allow() {
			writeError(w, http.StatusTooManyRequests, "RATE_LIMITED", "too many registration attempts, try again later")
			return
		}
		var req registerRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
			return
		}
		if !pm.Consume(req.PairingCode) {
			writeError(w, http.StatusUnauthorized, "INVALID_CODE", "invalid or expired pairing code — run `rfe-agent pair` on the computer to mint one")
			return
		}
		if req.Username == "" || len(req.Password) < 8 {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "username required and password must be at least 8 characters")
			return
		}
		if err := verifyDeviceProof(db, nonces, req.DeviceID, req.DevicePublicKey, req.Nonce, req.Signature, w, false); err != nil {
			return // verifyDeviceProof already wrote the error response
		}

		hash, err := security.HashPassword(req.Password)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", "failed to hash password")
			return
		}
		if err := db.CreateUser(req.Username, hash); err != nil {
			writeError(w, http.StatusConflict, "USERNAME_TAKEN", "that username is already registered on this computer")
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
		deviceID, err := db.UpsertDevice(req.DeviceID, req.DeviceLabel, token, req.DevicePublicKey)
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
