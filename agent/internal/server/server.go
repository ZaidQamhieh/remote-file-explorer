// Package server wires the agent's HTTP routes and middleware.
package server

import (
	"encoding/json"
	"net/http"
	"runtime"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/pairing"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/settings"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/thumbs"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/transfer"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/webui"
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
	UpdatesDir       string    // directory of downloadable APKs for in-app update
	TrashDir         string    // trash store root (XDG Trash on Linux; managed dir elsewhere)
	StartTime        time.Time // agent process start time (for uptime reporting)
	DataDir          string    // data directory path (for disk-space reporting)
}

// New builds the v1 router and wires all routes.
func New(cfg Config, db *store.DB, pm *pairing.Manager, tm *transfer.Manager, hub *EventHub) (http.Handler, error) {
	ops := fsops.NewWithSettings(cfg.Settings)

	thumbRenderer, err := thumbs.New(cfg.ThumbCacheDir)
	if err != nil {
		return nil, err
	}

	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recoverer)

	nonces := newNonceStore()

	r.Route("/v1", func(r chi.Router) {
		registerUnauthRoutes(r, cfg, db, pm, ops, nonces)

		// Authenticated, no path jail (non-filesystem endpoints).
		r.Group(func(r chi.Router) {
			r.Use(authMiddleware(db))
			r.Get("/status", statusHandler(cfg))
			r.Get("/throughput", throughputHandler())
			r.Post("/agent/restart", restartHandler())
		})

		// Authenticated sub-router.
		r.Group(func(r chi.Router) {
			r.Use(authMiddleware(db))
			// Narrows the shared ops to the calling device's jailRoot (H2),
			// if it has one. Must run after authMiddleware (needs the device
			// in context) and before any handler that resolves paths.
			r.Use(deviceJailMiddleware(ops))

			registerSettingsAndDeviceRoutes(r, cfg, db)
			registerShareRoutes(r, cfg, db, ops)
			r.Get("/system/drives", drivesHandler())
			r.Get("/search", searchHandler(ops))
			r.Get("/thumb", thumbHandler(ops, thumbRenderer))
			registerUpdateRoutes(r, cfg)
			registerFsRoutes(r, cfg, ops)
			r.Get("/events", sseHandler(hub))
			registerTrashRoutes(r, cfg, ops)
			registerContentRoutes(r, cfg, ops)
			registerTransferRoutes(r, tm, cfg, ops)
		})
	})

	// Web companion: browser-based agent control/status/settings UI, served
	// at the root (distinct from the /v1 API tree — chi matches the more
	// specific /v1 prefix first regardless of registration order).
	r.Mount("/", webui.Handler())

	return r, nil
}

// registerUnauthRoutes wires the routes reachable without a bearer token:
// health, pairing, registration, login, the device-identity challenge, and
// the single-use share-link fetch (rate-limited and expiring — see
// docs/r1-share-link-threat-model.md).
func registerUnauthRoutes(r chi.Router, cfg Config, db *store.DB, pm *pairing.Manager, ops *fsops.Ops, nonces *nonceStore) {
	r.Get("/health", healthHandler(cfg))
	r.Post("/auth/challenge", challengeHandler(nonces))
	r.Post("/pair", pairHandler(cfg, db, pm, nonces))
	r.Post("/register", registerHandler(cfg, db, pm, nonces))
	r.Post("/login", loginHandler(cfg, db, nonces))
	r.Get("/share/{token}", serveShareHandler(db, ops))
}

// registerSettingsAndDeviceRoutes wires agent settings, bandwidth limits, and
// paired-device management (list/jail/revoke/purge).
func registerSettingsAndDeviceRoutes(r chi.Router, cfg Config, db *store.DB) {
	r.Get("/settings", getSettingsHandler(cfg.Settings))
	r.Patch("/settings", patchSettingsHandler(cfg.Settings))
	r.Get("/settings/bandwidth", getBandwidthHandler(cfg.Settings))
	r.Put("/settings/bandwidth", putBandwidthHandler(cfg.Settings))
	r.Get("/devices", listDevicesHandler(db))
	r.Patch("/devices/{id}", setDeviceJailHandler())
	r.Delete("/devices/{id}", func(w http.ResponseWriter, req *http.Request) {
		id := chi.URLParam(req, "id")
		// ?purge=true permanently removes the row (used to clear revoked
		// devices); otherwise the device is revoked.
		if req.URL.Query().Get("purge") == "true" {
			deleteDeviceHandler(db)(w, req, id)
			return
		}
		revokeDeviceHandler(db)(w, req, id)
	})
	r.Post("/wol", wolRelayHandler())
}

// registerShareRoutes wires the authenticated R1 share-link management
// endpoints (mint/revoke/list — serving the file itself is unauthenticated,
// see registerUnauthRoutes).
func registerShareRoutes(r chi.Router, cfg Config, db *store.DB, ops *fsops.Ops) {
	r.Post("/share/mint", mintShareHandler(cfg, db, ops))
	r.Delete("/share/{tokenHash}", revokeShareHandler(db))
	r.Get("/share", listSharesHandler(db))
}

// registerUpdateRoutes wires the in-app updater's APK metadata/download.
func registerUpdateRoutes(r chi.Router, cfg Config) {
	r.Get("/app/latest", latestAppHandler(cfg.UpdatesDir))
	r.Get("/app/download", downloadAppHandler(cfg.UpdatesDir))
}

// registerFsRoutes wires the filesystem CRUD/browse endpoints.
func registerFsRoutes(r chi.Router, cfg Config, ops *fsops.Ops) {
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
	r.Get("/fs/checksum", checksumHandler(ops))
	r.Post("/fs/chmod", chmodHandler(ops))
	r.Get("/fs/archive", archivePeekHandler(ops))
	r.Post("/fs/checksums", batchChecksumHandler(ops))
	r.Get("/fs/recent", recentHandler(ops))
}

// registerTrashRoutes wires the trash list/restore/empty endpoints.
func registerTrashRoutes(r chi.Router, cfg Config, ops *fsops.Ops) {
	r.Get("/trash", listTrashHandler(cfg.TrashDir))
	r.Post("/trash/restore", restoreTrashHandler(ops, cfg.TrashDir))
	r.Delete("/trash", emptyTrashHandler(cfg.TrashDir))
}

// registerContentRoutes wires whole-file download/write (as opposed to the
// chunked transfer endpoints in registerTransferRoutes).
func registerContentRoutes(r chi.Router, cfg Config, ops *fsops.Ops) {
	r.Get("/content", downloadHandler(ops, cfg.Settings))
	r.Put("/content", writeContentHandler(ops))
}

// registerTransferRoutes wires the resumable chunked upload session
// endpoints.
func registerTransferRoutes(r chi.Router, tm *transfer.Manager, cfg Config, ops *fsops.Ops) {
	r.Post("/transfers", openTransferHandler(tm, ops))
	r.Get("/transfers/{id}", transferStatusHandler(tm))
	r.Put("/transfers/{id}/chunks/{n}", uploadChunkHandler(tm, cfg.Settings))
	r.Post("/transfers/{id}/complete", completeTransferHandler(tm, ops))
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
