// Package server — auth middleware.
package server

import (
	"context"
	"net"
	"net/http"
	"strings"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

type contextKey string

const deviceCtxKey contextKey = "device"

// opsCtxKey holds the per-request *fsops.Ops (see deviceJailMiddleware),
// already narrowed to the calling device's jailRoot when it has one.
const opsCtxKey contextKey = "ops"

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
			addr := r.RemoteAddr
			if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
				addr = host
			}
			ver := r.Header.Get("X-RFE-Client-Version")
			_ = db.TouchDevice(device.ID, addr, ver)

			ctx := context.WithValue(r.Context(), deviceCtxKey, device)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// deviceJailMiddleware reads the *store.Device placed in context by
// authMiddleware and, when it has a non-empty JailRoot (H2 per-device
// jail), narrows baseOps to that subtree via Ops.Jailed and injects the
// result into the request context under opsCtxKey. Handlers retrieve it via
// opsFromContext, which falls back to baseOps for devices with no jailRoot
// (and for any request that — for whatever reason — has no device in
// context), preserving today's behavior unchanged.
//
// This must run AFTER authMiddleware in the middleware chain (it depends on
// deviceCtxKey being populated), and BEFORE any handler that resolves paths.
func deviceJailMiddleware(baseOps *fsops.Ops) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ops := baseOps
			if device, ok := r.Context().Value(deviceCtxKey).(*store.Device); ok && device != nil && device.JailRoot != "" {
				ops = baseOps.Jailed(device.JailRoot)
			}
			ctx := context.WithValue(r.Context(), opsCtxKey, ops)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// opsFromContext returns the per-request *fsops.Ops injected by
// deviceJailMiddleware, or baseOps if the context has none (e.g. in unit
// tests that call handlers directly without the middleware chain).
func opsFromContext(ctx context.Context, baseOps *fsops.Ops) *fsops.Ops {
	if ops, ok := ctx.Value(opsCtxKey).(*fsops.Ops); ok && ops != nil {
		return ops
	}
	return baseOps
}
