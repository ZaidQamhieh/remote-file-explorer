// Package server — settings and device-management route handlers.
package server

import (
	"context"
	"encoding/json"
	"fmt"
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

// isAdminDevice reports whether d authenticated via /login or /register
// (the single account's password) rather than /pair (a one-time code for an
// ordinary device like the phone app) — see the via_login column comment in
// store.migrate. Only admin devices may manage OTHER devices: mint pairing
// codes, and toggle another device's jail/read-only/revoked state.
func isAdminDevice(d *store.Device) bool {
	return d != nil && d.ViaLogin
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
		"viaLogin":    d.ViaLogin,
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
// A device may always revoke ITSELF. Revoking another device additionally
// requires cur to be an admin device (authenticated via /login or /register —
// see isAdminDevice) — an ordinary paired device (e.g. the phone app, paired
// via /pair) still gets 403 FORBIDDEN. The `rfe-agent revoke`/`remove` admin
// CLI remains available regardless, for headless/PC-side use.
func revokeDeviceHandler(db *store.DB) func(http.ResponseWriter, *http.Request, string) {
	return func(w http.ResponseWriter, r *http.Request, id string) {
		cur := deviceFromContext(r)
		if cur == nil || (cur.ID != id && !isAdminDevice(cur)) {
			writeError(w, http.StatusForbidden, "FORBIDDEN", "managing other devices requires an admin (login) session or the PC")
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
// Same admin-or-self rule as revokeDeviceHandler.
func deleteDeviceHandler(db *store.DB) func(http.ResponseWriter, *http.Request, string) {
	return func(w http.ResponseWriter, r *http.Request, id string) {
		cur := deviceFromContext(r)
		if cur == nil || (cur.ID != id && !isAdminDevice(cur)) {
			writeError(w, http.StatusForbidden, "FORBIDDEN", "managing other devices requires an admin (login) session or the PC")
			return
		}
		if err := db.DeleteDevice(id); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// deviceJailBody is the PATCH /v1/devices/{id} request body: partial updates
// to another device's per-device path jail and/or read-only flag, mirroring
// settingsBody's pointer-field pattern (only fields present are changed).
type deviceJailBody struct {
	JailRoot *string `json:"jailRoot"`
	ReadOnly *bool   `json:"readOnly"`
}

// setDeviceJailHandler implements PATCH /v1/devices/{id}: sets a target
// device's per-device path jail and/or read-only flag. This is an admin-only
// operation (see isAdminDevice) — an ordinary paired device gets 403
// FORBIDDEN, same as before this endpoint had a real implementation. The
// `rfe-agent jail`/`readonly` admin CLI remains available for PC-side use.
func setDeviceJailHandler(db *store.DB, st *settings.Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		cur := deviceFromContext(r)
		if !isAdminDevice(cur) {
			writeError(w, http.StatusForbidden, "FORBIDDEN", "device access limits require an admin (login) session or the PC")
			return
		}
		id := chi.URLParam(r, "id")
		target, err := db.GetDeviceByID(id)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		if target == nil {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "no such device")
			return
		}
		var b deviceJailBody
		if err := json.NewDecoder(r.Body).Decode(&b); err != nil {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid JSON body")
			return
		}
		if b.JailRoot != nil {
			if _, err := SetDeviceJail(db, id, *b.JailRoot, st.Roots(), st.IsReadOnly()); err != nil {
				writeError(w, http.StatusBadRequest, "BAD_REQUEST", err.Error())
				return
			}
		}
		if b.ReadOnly != nil {
			if err := db.SetDeviceReadOnly(id, *b.ReadOnly); err != nil {
				writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
		}
		updated, err := db.GetDeviceByID(id)
		if err != nil || updated == nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", "device vanished mid-update")
			return
		}
		writeJSON(w, http.StatusOK, deviceJSON(*updated, cur))
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
// Shared by setDeviceJailHandler (PATCH /v1/devices/{id}, admin-only) and the
// `rfe-agent jail <device-id> <path>` CLI command, so both enforce the same
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
