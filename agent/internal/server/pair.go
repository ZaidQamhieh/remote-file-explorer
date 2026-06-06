// Package server — pair handler.
package server

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net/http"

	"github.com/google/uuid"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/pairing"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

type pairRequest struct {
	PairingCode     string `json:"pairingCode"`
	DeviceLabel     string `json:"deviceLabel"`
	ClientPublicKey string `json:"clientPublicKey"`
}

type pairResponse struct {
	DeviceToken     string `json:"deviceToken"`
	DeviceID        string `json:"deviceId"`
	AgentName       string `json:"agentName"`
	CertFingerprint string `json:"certFingerprint"`
}

func pairHandler(cfg Config, db *store.DB, pm *pairing.Manager) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
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

		deviceID := uuid.New().String()
		token, err := randomToken(32)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", "failed to generate token")
			return
		}

		if err := db.CreateDevice(deviceID, req.DeviceLabel, token); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}

		writeJSON(w, http.StatusOK, pairResponse{
			DeviceToken:     token,
			DeviceID:        deviceID,
			AgentName:       cfg.Name,
			CertFingerprint: cfg.CertFingerprint,
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
