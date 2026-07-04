// Package server — settings and device-management route handlers.
package server

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"path/filepath"

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
	ReadOnly        *bool     `json:"readOnly,omitempty"`
	Roots           *[]string `json:"roots,omitempty"`
	AgentName       *string   `json:"agentName,omitempty"`
	AllowSharing    *bool     `json:"allowSharing,omitempty"`
	PhotoBackupRoot *string   `json:"photoBackupRoot,omitempty"`
}

func getSettingsHandler(st *settings.Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"readOnly":        st.IsReadOnly(),
			"roots":           st.Roots(),
			"agentName":       st.AgentName(),
			"allowSharing":    st.IsAllowSharing(),
			"photoBackupRoot": st.PhotoBackupRoot(),
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
		if b.AllowSharing != nil {
			if err := st.SetAllowSharing(*b.AllowSharing); err != nil {
				writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
		}
		if b.PhotoBackupRoot != nil {
			if err := st.SetPhotoBackupRoot(*b.PhotoBackupRoot); err != nil {
				writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"readOnly":        st.IsReadOnly(),
			"roots":           st.Roots(),
			"agentName":       st.AgentName(),
			"allowSharing":    st.IsAllowSharing(),
			"photoBackupRoot": st.PhotoBackupRoot(),
		})
	}
}

// --------- GET /settings/bandwidth ---------

func getBandwidthHandler(st *settings.Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"maxUploadBytesPerSec":   st.MaxUploadBytesPerSec(),
			"maxDownloadBytesPerSec": st.MaxDownloadBytesPerSec(),
		})
	}
}

// --------- PUT /settings/bandwidth ---------

func putBandwidthHandler(st *settings.Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var b struct {
			MaxUploadBytesPerSec   *int64 `json:"maxUploadBytesPerSec"`
			MaxDownloadBytesPerSec *int64 `json:"maxDownloadBytesPerSec"`
		}
		if err := json.NewDecoder(r.Body).Decode(&b); err != nil {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid JSON body")
			return
		}
		if b.MaxUploadBytesPerSec != nil {
			if err := st.SetMaxUploadBytesPerSec(*b.MaxUploadBytesPerSec); err != nil {
				writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
		}
		if b.MaxDownloadBytesPerSec != nil {
			if err := st.SetMaxDownloadBytesPerSec(*b.MaxDownloadBytesPerSec); err != nil {
				writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"maxUploadBytesPerSec":   st.MaxUploadBytesPerSec(),
			"maxDownloadBytesPerSec": st.MaxDownloadBytesPerSec(),
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
		"readOnly":    d.ReadOnly,
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
//
// A paired device may only manage ITSELF: targeting any other device id is
// rejected with 403 FORBIDDEN. Managing other devices is a PC-side operation
// (the `rfe-agent revoke`/`remove` admin CLI).
func revokeDeviceHandler(db *store.DB) func(http.ResponseWriter, *http.Request, string) {
	return func(w http.ResponseWriter, r *http.Request, id string) {
		cur := deviceFromContext(r)
		if cur == nil || cur.ID != id {
			writeError(w, http.StatusForbidden, "FORBIDDEN", "managing other devices must be done on the PC")
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
// devices from the list; reached via DELETE /v1/devices/{id}?purge=true).
//
// A paired device may only manage ITSELF: targeting any other device id is
// rejected with 403 FORBIDDEN. Managing other devices is a PC-side operation
// (the `rfe-agent remove` admin CLI).
func deleteDeviceHandler(db *store.DB) func(http.ResponseWriter, *http.Request, string) {
	return func(w http.ResponseWriter, r *http.Request, id string) {
		cur := deviceFromContext(r)
		if cur == nil || cur.ID != id {
			writeError(w, http.StatusForbidden, "FORBIDDEN", "managing other devices must be done on the PC")
			return
		}
		if err := db.DeleteDevice(id); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// setDeviceJailHandler implements PATCH /v1/devices/{id}.
//
// Per-device path jails are a PC-side configuration concern (see
// `rfe-agent jail <device-id> <path>`): every authenticated app caller gets
// 403 FORBIDDEN, regardless of which device — including itself — it targets.
// The route stays registered (403, not 405) so the app can detect the
// capability is unavailable rather than getting a generic "no such route".
func setDeviceJailHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "device access limits are configured on the PC")
	}
}

// ValidateJailRoot validates a candidate per-device jailRoot against the
// agent's configured global roots, returning the cleaned path to persist (or
// "" to clear the per-device restriction).
//
// jailRoot must be either "" (clear the per-device restriction) or an
// absolute, cleaned path that resolves within the agent's configured global
// roots (roots) — if any roots are configured. A jailRoot outside the global
// roots would widen access if it were ever honored on its own, so it is
// rejected outright rather than accepted and silently clamped: better to fail
// loudly than to let an admin believe a jail is in effect when
// fsops.Ops.Jailed would in fact deny everything.
//
// Shared by setDeviceJailHandler's predecessor and the `rfe-agent jail` admin
// CLI command, so both enforce the same containment rule.
func ValidateJailRoot(jailRoot string, roots []string, readOnly bool) (string, error) {
	if jailRoot == "" {
		return "", nil
	}
	clean := filepath.Clean(jailRoot)
	if !filepath.IsAbs(clean) {
		return "", fmt.Errorf("jailRoot must be an absolute path")
	}
	if len(roots) > 0 {
		// Reuse the same jail-resolution logic used for ordinary path access
		// (cleans + resolves symlinks + checks containment) so a jailRoot
		// that only "looks" contained via a symlink trick is rejected the
		// same way an escaping request would be.
		baseOps := fsops.New(roots, readOnly)
		if _, err := baseOps.Resolve(clean); err != nil {
			return "", fmt.Errorf("jailRoot must resolve within the agent's configured roots")
		}
	}
	return clean, nil
}

// SetDeviceJail validates jailRoot against the agent's configured global
// roots (via ValidateJailRoot) and, if valid, persists it as device id's
// per-device path jail (db.SetDeviceJail). Returns the cleaned jailRoot that
// was stored.
//
// This is the reusable core that previously lived in setDeviceJailHandler
// (PATCH /v1/devices/{id}, now PC-only/403); it is exported so the
// `rfe-agent jail <device-id> <path>` admin CLI command can reuse the same
// validation and persistence logic.
func SetDeviceJail(db *store.DB, id, jailRoot string, roots []string, readOnly bool) (string, error) {
	clean, err := ValidateJailRoot(jailRoot, roots, readOnly)
	if err != nil {
		return "", err
	}
	if err := db.SetDeviceJail(id, clean); err != nil {
		return "", err
	}
	return clean, nil
}
