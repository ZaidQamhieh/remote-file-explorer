// Package server — settings and device-management route handlers.
package server

import (
	"context"
	"encoding/json"
	"net/http"
	"path/filepath"

	"github.com/go-chi/chi/v5"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/settings"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

// withDevice injects a device into a context (test seam mirroring authMiddleware).
func withDevice(ctx context.Context, d *store.Device) context.Context {
	return context.WithValue(ctx, deviceCtxKey, d)
}

func deviceFromContext(r *http.Request) *store.Device {
	d, _ := r.Context().Value(deviceCtxKey).(*store.Device)
	return d
}

type settingsBody struct {
	ReadOnly  *bool     `json:"readOnly,omitempty"`
	Roots     *[]string `json:"roots,omitempty"`
	AgentName *string   `json:"agentName,omitempty"`
}

func getSettingsHandler(st *settings.Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"readOnly":  st.IsReadOnly(),
			"roots":     st.Roots(),
			"agentName": st.AgentName(),
		})
	}
}

func patchSettingsHandler(st *settings.Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var b settingsBody
		if err := json.NewDecoder(r.Body).Decode(&b); err != nil {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid JSON body")
			return
		}
		if b.ReadOnly != nil {
			if err := st.SetReadOnly(*b.ReadOnly); err != nil {
				writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
		}
		if b.Roots != nil {
			if err := st.SetRoots(*b.Roots); err != nil {
				writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
		}
		if b.AgentName != nil {
			if err := st.SetAgentName(*b.AgentName); err != nil {
				writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"readOnly":  st.IsReadOnly(),
			"roots":     st.Roots(),
			"agentName": st.AgentName(),
		})
	}
}

// deviceJSON builds the Device JSON shape shared by GET /devices (list) and
// PATCH /devices/{id} (single updated device).
func deviceJSON(d store.Device, cur *store.Device) map[string]any {
	return map[string]any{
		"id":          d.ID,
		"label":       d.Label,
		"created":     d.Created.Unix(),
		"lastSeen":    d.LastSeen.Unix(),
		"revoked":     d.Revoked,
		"current":     cur != nil && cur.ID == d.ID,
		"lastAddress": d.LastAddress,
		"lastVersion": d.LastVersion,
		"jailRoot":    d.JailRoot,
	}
}

func listDevicesHandler(db *store.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		devices, err := db.ListDevices()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		cur := deviceFromContext(r)
		out := make([]map[string]any, 0, len(devices))
		for _, d := range devices {
			out = append(out, deviceJSON(d, cur))
		}
		writeJSON(w, http.StatusOK, out)
	}
}

// revokeDeviceHandler revokes device `id`. The third arg is the URL path param
// (the route wrapper passes chi.URLParam so this stays unit-testable).
func revokeDeviceHandler(db *store.DB) func(http.ResponseWriter, *http.Request, string) {
	return func(w http.ResponseWriter, r *http.Request, id string) {
		cur := deviceFromContext(r)
		if cur != nil && cur.ID == id {
			writeError(w, http.StatusConflict, "CONFLICT", "cannot revoke the device you are using")
			return
		}
		if err := db.RevokeDevice(id); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// deleteDeviceHandler permanently removes device `id` (used to clear revoked
// devices from the list). Refuses to delete the device making the request.
func deleteDeviceHandler(db *store.DB) func(http.ResponseWriter, *http.Request, string) {
	return func(w http.ResponseWriter, r *http.Request, id string) {
		cur := deviceFromContext(r)
		if cur != nil && cur.ID == id {
			writeError(w, http.StatusConflict, "CONFLICT", "cannot remove the device you are using")
			return
		}
		if err := db.DeleteDevice(id); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// setDeviceJailHandler implements PATCH /v1/devices/{id} (H2 per-device path
// jail). Body: {"jailRoot": "<absolute path, or empty string to clear>"}.
//
// Validation: jailRoot must be either "" (clear the per-device restriction)
// or an absolute, cleaned path that resolves within the agent's configured
// global roots (st.Roots()) — if any roots are configured. A jailRoot
// outside the global roots would widen access if it were ever honored on its
// own, so it is rejected outright (400 INVALID) rather than accepted and
// silently clamped: better to fail loudly than to let an admin believe a
// jail is in effect when fsops.Ops.Jailed would in fact deny everything.
//
// On success, returns the updated Device in the same JSON shape as
// GET /devices (200).
func setDeviceJailHandler(db *store.DB, st settingsRootsView) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := chi.URLParam(r, "id")

		var body struct {
			JailRoot *string `json:"jailRoot"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid JSON body")
			return
		}
		if body.JailRoot == nil {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "jailRoot required")
			return
		}

		jailRoot := *body.JailRoot
		if jailRoot != "" {
			clean := filepath.Clean(jailRoot)
			if !filepath.IsAbs(clean) {
				writeError(w, http.StatusBadRequest, "INVALID", "jailRoot must be an absolute path")
				return
			}
			if roots := st.Roots(); len(roots) > 0 {
				// Reuse the same jail-resolution logic used for ordinary path
				// access (cleans + resolves symlinks + checks containment) so
				// a jailRoot that only "looks" contained via a symlink trick
				// is rejected the same way an escaping request would be.
				baseOps := fsops.New(roots, st.IsReadOnly())
				if _, err := baseOps.Resolve(clean); err != nil {
					writeError(w, http.StatusBadRequest, "INVALID", "jailRoot must resolve within the agent's configured roots")
					return
				}
			}
			jailRoot = clean
		}

		if err := db.SetDeviceJail(id, jailRoot); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}

		updated, err := db.GetDeviceByID(id)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		if updated == nil {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "device not found")
			return
		}

		cur := deviceFromContext(r)
		writeJSON(w, http.StatusOK, deviceJSON(*updated, cur))
	}
}

// settingsRootsView is the subset of *settings.Store needed to validate a
// jailRoot against the agent's configured global roots. Defined as an
// interface so tests can pass a minimal fake instead of a full
// *settings.Store.
type settingsRootsView interface {
	Roots() []string
	IsReadOnly() bool
}
