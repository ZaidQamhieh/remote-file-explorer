// Package server — in-app update route handlers (Android APK delivery).
package server

import (
	"net/http"
	"os"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/updates"
)

func latestAppHandler(dir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rel, err := updates.Latest(dir)
		if err != nil {
			writeInternal(w, "latest app", err)
			return
		}
		if rel == nil {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		writeJSON(w, http.StatusOK, rel)
	}
}

func downloadAppHandler(dir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rel, err := updates.Latest(dir)
		if err != nil {
			writeInternal(w, "download app", err)
			return
		}
		if rel == nil {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "no update available")
			return
		}
		f, err := os.Open(updates.Path(dir, rel))
		if err != nil {
			writeInternal(w, "download app", err)
			return
		}
		defer f.Close()
		info, err := f.Stat()
		if err != nil {
			writeInternal(w, "download app", err)
			return
		}
		w.Header().Set("Content-Type", "application/vnd.android.package-archive")
		// ServeContent adds Range support, Content-Length, 206/416 handling.
		http.ServeContent(w, r, rel.Filename, info.ModTime(), f)
	}
}
