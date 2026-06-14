// Package server — thumbnail handler.
package server

import (
	"errors"
	"net/http"
	"os"
	"strconv"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/thumbs"
)

// defaultThumbSize matches the default declared in protocol/openapi.yaml.
const defaultThumbSize = 256

// maxThumbSize caps the requested size to keep rendering cost bounded.
const maxThumbSize = 1024

// --------- /thumb GET ---------

func thumbHandler(ops *fsops.Ops, rn *thumbs.Renderer) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
		path := r.URL.Query().Get("path")
		if path == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "path required")
			return
		}

		size := defaultThumbSize
		if raw := r.URL.Query().Get("size"); raw != "" {
			n, err := strconv.Atoi(raw)
			if err != nil || n <= 0 {
				writeError(w, http.StatusBadRequest, "BAD_REQUEST", "size must be a positive integer")
				return
			}
			size = n
		}
		if size > maxThumbSize {
			size = maxThumbSize
		}

		resolved, err := ops.Resolve(path)
		if err != nil {
			handleFsError(w, err)
			return
		}

		data, err := rn.Get(resolved, size)
		if err != nil {
			if errors.Is(err, thumbs.ErrNotSupported) || os.IsNotExist(err) {
				writeError(w, http.StatusNotFound, "NOT_AVAILABLE", "no thumbnail available for this file")
				return
			}
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}

		w.Header().Set("Content-Type", "image/jpeg")
		w.Header().Set("Cache-Control", "public, max-age=86400")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(data)
	}
}
