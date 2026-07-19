// Package server — chmod handler.
package server

import (
	"io/fs"
	"net/http"
	"os"
	"strconv"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
)

func chmodHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
		if ops.IsReadOnly() {
			writeError(w, http.StatusForbidden, "READ_ONLY", fsops.ErrReadOnly.Error())
			return
		}
		var req struct {
			Path string `json:"path"`
			Mode string `json:"mode"`
		}
		if !decodeJSONBody(w, r, &req) {
			return
		}
		if req.Path == "" || req.Mode == "" {
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
				writeError(w, http.StatusForbidden, "FORBIDDEN", "permission denied")
				return
			}
			writeInternal(w, "chmod", err)
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
