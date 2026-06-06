// Package server wires the agent's HTTP routes and middleware.
package server

import (
	"encoding/json"
	"net/http"
	"runtime"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

// Config holds the runtime settings the server needs.
type Config struct {
	Name     string
	Version  string
	ReadOnly bool
}

// New builds the v1 router. Phase 0 ships /health; later phases mount the
// authenticated filesystem, transfer, search, and event routes here.
func New(cfg Config) http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recoverer)

	r.Route("/v1", func(r chi.Router) {
		r.Get("/health", healthHandler(cfg))
		// TODO(phase1+): r.Post("/pair", ...) and an authenticated sub-router
		// for /fs, /content, /transfers, /search, /thumb, /events.
	})

	return r
}

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

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
