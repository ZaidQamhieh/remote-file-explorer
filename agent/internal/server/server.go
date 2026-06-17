// Package server wires the agent's HTTP routes and middleware.
package server

import (
	"encoding/json"
	"net/http"
	"runtime"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/pairing"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/settings"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/thumbs"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/transfer"
)

// Config holds the runtime settings the server needs.
type Config struct {
	Name             string
	Version          string
	CertFingerprint  string
	Address          string // LAN address used in QR payload / health response
	TailscaleAddress string // Tailscale address, if detected
	MACAddress       string // MAC address of the LAN interface (for Wake-on-LAN)
	ThumbCacheDir    string // directory for on-disk thumbnail cache
	Settings         *settings.Store
	UpdatesDir       string // directory of downloadable APKs for in-app update
	TrashDir         string // trash store root (XDG Trash on Linux; managed dir elsewhere)
}

// New builds the v1 router and wires all routes.
func New(cfg Config, db *store.DB, pm *pairing.Manager, tm *transfer.Manager) (http.Handler, error) {
	ops := fsops.NewWithSettings(cfg.Settings)

	thumbRenderer, err := thumbs.New(cfg.ThumbCacheDir)
	if err != nil {
		return nil, err
	}

	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recoverer)

	r.Route("/v1", func(r chi.Router) {
		// Unauthenticated.
		r.Get("/health", healthHandler(cfg))
		r.Post("/pair", pairHandler(cfg, db, pm))

		// Authenticated sub-router.
		r.Group(func(r chi.Router) {
			r.Use(authMiddleware(db))
			// Narrows the shared ops to the calling device's jailRoot (H2),
			// if it has one. Must run after authMiddleware (needs the device
			// in context) and before any handler that resolves paths.
			r.Use(deviceJailMiddleware(ops))

			// Settings & devices
			r.Get("/settings", getSettingsHandler(cfg.Settings))
			r.Patch("/settings", patchSettingsHandler(cfg.Settings))
			r.Get("/devices", listDevicesHandler(db))
			r.Patch("/devices/{id}", setDeviceJailHandler())
			r.Delete("/devices/{id}", func(w http.ResponseWriter, req *http.Request) {
				id := chi.URLParam(req, "id")
				// ?purge=true permanently removes the row (used to clear
				// revoked devices); otherwise the device is revoked.
				if req.URL.Query().Get("purge") == "true" {
					deleteDeviceHandler(db)(w, req, id)
					return
				}
				revokeDeviceHandler(db)(w, req, id)
			})

			// Drives
			r.Get("/system/drives", drivesHandler())

			// Search
			r.Get("/search", searchHandler(ops))

			// Thumbnails
			r.Get("/thumb", thumbHandler(ops, thumbRenderer))

			// In-app updater
			r.Get("/app/latest", latestAppHandler(cfg.UpdatesDir))
			r.Get("/app/download", downloadAppHandler(cfg.UpdatesDir))

			// Filesystem
			r.Get("/fs", listDirHandler(ops))
			r.Delete("/fs", deleteHandler(ops, cfg.TrashDir))
			r.Post("/fs/folder", createFolderHandler(ops))
			r.Post("/fs/file", createFileHandler(ops))
			r.Patch("/fs/rename", renameHandler(ops))
			r.Post("/fs/copy", copyHandler(ops))
			r.Post("/fs/move", moveHandler(ops))
			r.Post("/fs/compress", compressHandler(ops))
			r.Post("/fs/extract", extractHandler(ops))
			r.Get("/fs/meta", metaHandler(ops))

			// Trash
			r.Get("/trash", listTrashHandler(cfg.TrashDir))
			r.Post("/trash/restore", restoreTrashHandler(ops, cfg.TrashDir))
			r.Delete("/trash", emptyTrashHandler(cfg.TrashDir))

			// Download / write content
			r.Get("/content", downloadHandler(ops))
			r.Put("/content", writeContentHandler(ops))

			// Upload / transfers
			r.Post("/transfers", openTransferHandler(tm, ops))
			r.Get("/transfers/{id}", transferStatusHandler(tm))
			r.Put("/transfers/{id}/chunks/{n}", uploadChunkHandler(tm))
			r.Post("/transfers/{id}/complete", completeTransferHandler(tm, ops))
		})
	})

	return r, nil
}

// --------- helpers ---------

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

type apiError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, apiError{Code: code, Message: message})
}

// --------- health ---------

func healthHandler(cfg Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Surfacing the agent's known addresses lets an already-paired app
		// learn the Tailscale (or LAN) address it didn't capture at pairing
		// time, simply by reaching the agent successfully via either one.
		// macAddress is included so the app can cache it for Wake-on-LAN
		// when the host is asleep (and thus unreachable).
		resp := map[string]any{
			"status":           "ok",
			"name":             cfg.Settings.AgentName(),
			"version":          cfg.Version,
			"os":               runtime.GOOS,
			"readOnly":         cfg.Settings.IsReadOnly(),
			"address":          cfg.Address,
			"tailscaleAddress": cfg.TailscaleAddress,
		}
		if cfg.MACAddress != "" {
			resp["macAddress"] = cfg.MACAddress
		}
		writeJSON(w, http.StatusOK, resp)
	}
}
