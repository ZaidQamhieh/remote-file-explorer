// Package server — auth middleware.
package server

import (
	"context"
	"net/http"
	"strings"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

type contextKey string

const deviceCtxKey contextKey = "device"

// authMiddleware validates the Bearer token against the device store.
// Returns 401 if missing/invalid/revoked.
func authMiddleware(db *store.DB) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			hdr := r.Header.Get("Authorization")
			if hdr == "" {
				writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "missing Authorization header")
				return
			}
			parts := strings.SplitN(hdr, " ", 2)
			if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
				writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "invalid Authorization header format")
				return
			}
			token := strings.TrimSpace(parts[1])
			device, err := db.DeviceByToken(token)
			if err != nil {
				writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
			if device == nil || device.Revoked {
				writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "invalid or revoked token")
				return
			}
			_ = db.TouchDevice(device.ID)

			ctx := context.WithValue(r.Context(), deviceCtxKey, device)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}
