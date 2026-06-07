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
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/transfer"
)

// Config holds the runtime settings the server needs.
type Config struct {
	Name            string
	Version         string
	ReadOnly        bool
	CertFingerprint string
	Address         string // LAN address used in QR payload
	AllowedRoots    []string
}

// New builds the v1 router and wires all routes.
func New(cfg Config, db *store.DB, pm *pairing.Manager, tm *transfer.Manager) http.Handler {
	ops := fsops.New(cfg.AllowedRoots, cfg.ReadOnly)

	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recoverer)

	r.Route("/v1", func(r chi.Router) {
		// Unauthenticated.
		r.Get("/health", healthHandler(cfg))
		r.Post("/pair", pairHandler(cfg, db, pm))

		// Phase-2 stubs (unauthenticated paths that will never match auth).
		r.Get("/thumb", notImplementedHandler)

		// Authenticated sub-router.
		r.Group(func(r chi.Router) {
			r.Use(authMiddleware(db))

			// Drives
			r.Get("/system/drives", drivesHandler())

			// Search
			r.Get("/search", searchHandler(ops))

			// Filesystem
			r.Get("/fs", listDirHandler(ops))
			r.Delete("/fs", deleteHandler(ops))
			r.Post("/fs/folder", createFolderHandler(ops))
			r.Post("/fs/file", createFileHandler(ops))
			r.Patch("/fs/rename", renameHandler(ops))
			r.Post("/fs/copy", copyHandler(ops))
			r.Post("/fs/move", moveHandler(ops))
			r.Get("/fs/meta", metaHandler(ops))

			// Download
			r.Get("/content", downloadHandler(ops))

			// Upload / transfers
			r.Post("/transfers", openTransferHandler(tm, ops))
			r.Get("/transfers/{id}", transferStatusHandler(tm))
			r.Put("/transfers/{id}/chunks/{n}", uploadChunkHandler(tm))
			r.Post("/transfers/{id}/complete", completeTransferHandler(tm, ops))
		})
	})

	return r
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

func notImplementedHandler(w http.ResponseWriter, _ *http.Request) {
	writeError(w, http.StatusNotImplemented, "NOT_IMPLEMENTED", "this endpoint is not yet implemented")
}

// --------- health ---------

func healthHandler(cfg Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"status":   "ok",
			"name":     cfg.Name,
			"version":  cfg.Version,
			"os":       runtime.GOOS,
			"readOnly": cfg.ReadOnly,
		})
	}
}
