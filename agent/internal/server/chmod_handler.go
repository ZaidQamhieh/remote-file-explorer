// Package server — chmod handler.
package server

import (
	"encoding/json"
	"io/fs"
	"net/http"
	"os"
	"strconv"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
)

func chmodHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
		var req struct {
			Path string `json:"path"`
			Mode string `json:"mode"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Path == "" || req.Mode == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "path and mode required")
			return
		}

		parsed, err := strconv.ParseUint(req.Mode, 8, 32)
		if err != nil {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid octal mode: "+req.Mode)
			return
		}

		resolved, err := ops.Resolve(req.Path)
		if err != nil {
			handleFsError(w, err)
			return
		}

		if err := os.Chmod(resolved, fs.FileMode(parsed)); err != nil {
			if os.IsNotExist(err) {
				handleFsError(w, fsops.ErrNotFound)
				return
			}
			if os.IsPermission(err) {
				writeError(w, http.StatusForbidden, "FORBIDDEN", err.Error())
				return
			}
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}

		entry, err := ops.Meta(resolved)
		if err != nil {
			handleFsError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, entry)
	}
}
