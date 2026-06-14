// Package server — settings and device-management route handlers.
package server

import (
	"context"
	"encoding/json"
	"net/http"

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
			out = append(out, map[string]any{
				"id":          d.ID,
				"label":       d.Label,
				"created":     d.Created.Unix(),
				"lastSeen":    d.LastSeen.Unix(),
				"revoked":     d.Revoked,
				"current":     cur != nil && cur.ID == d.ID,
				"lastAddress": d.LastAddress,
				"lastVersion": d.LastVersion,
			})
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
