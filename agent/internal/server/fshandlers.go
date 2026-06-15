// Package server — filesystem route handlers.
package server

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
)

// --------- /system/drives ---------

func drivesHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		drives, err := fsops.Drives()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		writeJSON(w, http.StatusOK, drives)
	}
}

// --------- /fs GET (list dir) ---------

func listDirHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
		path := r.URL.Query().Get("path")
		if path == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "path query param required")
			return
		}
		cursor := r.URL.Query().Get("cursor")
		limit := 200
		if l := r.URL.Query().Get("limit"); l != "" {
			if n, err := strconv.Atoi(l); err == nil && n > 0 {
				limit = n
			}
		}
		listing, err := ops.ListDir(path, cursor, limit)
		if err != nil {
			handleFsError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, listing)
	}
}

// --------- /fs DELETE (batch delete) ---------

func deleteHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
		var paths []string

		// Accept either ?path= query param or JSON body with paths array.
		if p := r.URL.Query().Get("path"); p != "" {
			paths = append(paths, p)
		}

		// Parse optional body.
		if r.ContentLength > 0 {
			var body struct {
				Paths []string `json:"paths"`
			}
			if err := json.NewDecoder(r.Body).Decode(&body); err == nil {
				paths = append(paths, body.Paths...)
			}
		}

		if len(paths) == 0 {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "no paths specified")
			return
		}
		results := ops.Delete(paths)
		writeJSON(w, http.StatusOK, map[string]any{"results": results})
	}
}

// --------- /fs/folder POST ---------

func createFolderHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
		var req struct {
			Path string `json:"path"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Path == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "path required")
			return
		}
		entry, err := ops.CreateFolder(req.Path)
		if err != nil {
			handleFsError(w, err)
			return
		}
		writeJSON(w, http.StatusCreated, entry)
	}
}

// --------- /fs/file POST ---------

func createFileHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
		var req struct {
			Path string `json:"path"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Path == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "path required")
			return
		}
		entry, err := ops.CreateFile(req.Path)
		if err != nil {
			handleFsError(w, err)
			return
		}
		writeJSON(w, http.StatusCreated, entry)
	}
}

// --------- /fs/rename PATCH ---------

func renameHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
		var req struct {
			Src string `json:"src"`
			Dst string `json:"dst"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Src == "" || req.Dst == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "src and dst required")
			return
		}
		entry, err := ops.Rename(req.Src, req.Dst)
		if err != nil {
			handleFsError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, entry)
	}
}

// --------- /fs/copy POST ---------

func copyHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
		var req struct {
			Sources   []string `json:"sources"`
			DestDir   string   `json:"destDir"`
			Dup       bool     `json:"duplicate"`
			Overwrite bool     `json:"overwrite"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.Sources) == 0 || req.DestDir == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "sources and destDir required")
			return
		}
		results := ops.Copy(req.Sources, req.DestDir, req.Dup, req.Overwrite)
		writeJSON(w, http.StatusAccepted, map[string]any{"results": results})
	}
}

// --------- /fs/move POST ---------

func moveHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
		var req struct {
			Sources   []string `json:"sources"`
			DestDir   string   `json:"destDir"`
			Dup       bool     `json:"duplicate"`
			Overwrite bool     `json:"overwrite"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.Sources) == 0 || req.DestDir == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "sources and destDir required")
			return
		}
		results := ops.Move(req.Sources, req.DestDir, req.Dup, req.Overwrite)
		writeJSON(w, http.StatusAccepted, map[string]any{"results": results})
	}
}

// --------- /fs/compress POST ---------

func compressHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
		var req struct {
			Sources []string `json:"sources"`
			Dest    string   `json:"dest"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.Sources) == 0 || req.Dest == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "sources and dest required")
			return
		}
		entry, err := ops.Compress(req.Sources, req.Dest)
		if err != nil {
			handleFsError(w, err)
			return
		}
		writeJSON(w, http.StatusCreated, entry)
	}
}

// --------- /fs/extract POST ---------

func extractHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
		var req struct {
			Archive string `json:"archive"`
			DestDir string `json:"destDir"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Archive == "" || req.DestDir == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "archive and destDir required")
			return
		}
		entry, err := ops.Extract(req.Archive, req.DestDir)
		if err != nil {
			handleFsError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, entry)
	}
}

// --------- /fs/meta GET ---------

func metaHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
		path := r.URL.Query().Get("path")
		if path == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "path required")
			return
		}
		entry, err := ops.Meta(path)
		if err != nil {
			handleFsError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, entry)
	}
}

// --------- error mapping ---------

func handleFsError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, fsops.ErrForbidden):
		writeError(w, http.StatusForbidden, "FORBIDDEN", err.Error())
	case errors.Is(err, fsops.ErrNotFound):
		writeError(w, http.StatusNotFound, "PATH_NOT_FOUND", err.Error())
	case errors.Is(err, fsops.ErrReadOnly):
		writeError(w, http.StatusForbidden, "READ_ONLY", err.Error())
	case errors.Is(err, fsops.ErrUnsupported):
		writeError(w, http.StatusBadRequest, "UNSUPPORTED_FORMAT", err.Error())
	case errors.Is(err, fsops.ErrConflict):
		writeError(w, http.StatusConflict, "CONFLICT", err.Error())
	case errors.Is(err, fsops.ErrStale):
		writeError(w, http.StatusConflict, "STALE_WRITE", err.Error())
	default:
		writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
	}
}
