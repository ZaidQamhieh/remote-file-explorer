// Package server — transfer (upload) + content (download) handlers.
package server

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/transfer"
)

// --------- /content GET ---------

func downloadHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Query().Get("path")
		if path == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "path required")
			return
		}
		resolved, err := ops.Resolve(path)
		if err != nil {
			handleFsError(w, err)
			return
		}
		f, err := os.Open(resolved)
		if err != nil {
			if os.IsNotExist(err) {
				writeError(w, http.StatusNotFound, "PATH_NOT_FOUND", "file not found")
			} else {
				writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			}
			return
		}
		defer f.Close()

		info, err := f.Stat()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		// http.ServeContent handles Range, 206, 416, Content-Type, ETag, etc.
		http.ServeContent(w, r, info.Name(), info.ModTime(), f)
	}
}

// MaxContentBytes caps the size of a PUT /v1/content request body.
const MaxContentBytes int64 = 5 << 20 // 5 MiB

// --------- /content PUT ---------

func writeContentHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Query().Get("path")
		if path == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "path required")
			return
		}

		var baseModified *time.Time
		if bm := r.URL.Query().Get("baseModified"); bm != "" {
			t, err := time.Parse(time.RFC3339Nano, bm)
			if err != nil {
				writeError(w, http.StatusBadRequest, "BAD_REQUEST", "baseModified must be RFC3339")
				return
			}
			baseModified = &t
		}

		r.Body = http.MaxBytesReader(w, r.Body, MaxContentBytes)
		data, err := io.ReadAll(r.Body)
		if err != nil {
			var maxErr *http.MaxBytesError
			if errors.As(err, &maxErr) {
				writeError(w, http.StatusRequestEntityTooLarge, "PAYLOAD_TOO_LARGE", "content exceeds maximum size of 5MiB")
				return
			}
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "failed to read request body")
			return
		}

		entry, err := ops.WriteContent(path, data, baseModified)
		if err != nil {
			handleFsError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, entry)
	}
}

// maxChunkSize caps the client-chosen chunkSize for an upload session.
// Chunks are buffered fully in memory (see uploadChunkHandler), so an
// unbounded chunkSize would let a client force large allocations.
const maxChunkSize = 32 * 1024 * 1024 // 32 MiB

// --------- POST /transfers ---------

func openTransferHandler(tm *transfer.Manager, ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Path      string `json:"path"`
			Size      int64  `json:"size"`
			SHA256    string `json:"sha256"`
			ChunkSize int    `json:"chunkSize"`
			Overwrite bool   `json:"overwrite"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
			return
		}
		if req.Path == "" || req.SHA256 == "" || req.ChunkSize <= 0 {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "path, sha256, and chunkSize required")
			return
		}
		if req.Size < 0 {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "size must not be negative")
			return
		}
		if req.ChunkSize > maxChunkSize {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "chunkSize exceeds maximum of 32MiB")
			return
		}
		// Validate path is in jail.
		resolved, err := ops.Resolve(req.Path)
		if err != nil {
			handleFsError(w, err)
			return
		}

		id := uuid.New().String()
		t, err := tm.OpenSession(id, resolved, req.Size, req.ChunkSize, req.SHA256, req.Overwrite)
		if err != nil {
			if errors.Is(err, transfer.ErrDestinationExists) {
				writeError(w, http.StatusConflict, "CONFLICT", "destination already exists")
				return
			}
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		writeJSON(w, http.StatusCreated, transferSession(t))
	}
}

// --------- GET /transfers/{id} ---------

func transferStatusHandler(tm *transfer.Manager) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := chi.URLParam(r, "id")
		t, err := tm.Status(id)
		if err != nil {
			if errors.Is(err, transfer.ErrNotFound) {
				writeError(w, http.StatusNotFound, "NOT_FOUND", "transfer not found")
			} else {
				writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			}
			return
		}
		writeJSON(w, http.StatusOK, transferSession(t))
	}
}

// --------- PUT /transfers/{id}/chunks/{n} ---------

func uploadChunkHandler(tm *transfer.Manager) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := chi.URLParam(r, "id")
		nStr := chi.URLParam(r, "n")
		n, err := strconv.Atoi(nStr)
		if err != nil {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid chunk index")
			return
		}
		chunkSHA256 := r.Header.Get("X-Chunk-Sha256")
		if chunkSHA256 == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "X-Chunk-Sha256 header required")
			return
		}

		t, err := tm.Status(id)
		if err != nil {
			if errors.Is(err, transfer.ErrNotFound) {
				writeError(w, http.StatusNotFound, "NOT_FOUND", "transfer not found")
				return
			}
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}

		// Cap the request body to the session's chunk size. The final chunk
		// may be smaller, which is fine since this is just an upper bound.
		r.Body = http.MaxBytesReader(w, r.Body, int64(t.ChunkSize))
		data, err := io.ReadAll(r.Body)
		if err != nil {
			var maxErr *http.MaxBytesError
			if errors.As(err, &maxErr) {
				writeError(w, http.StatusRequestEntityTooLarge, "PAYLOAD_TOO_LARGE", "chunk exceeds session chunk size")
				return
			}
			writeError(w, http.StatusInternalServerError, "INTERNAL", "failed to read body")
			return
		}

		if err := tm.WriteChunk(id, n, data, chunkSHA256); err != nil {
			if errors.Is(err, transfer.ErrNotFound) {
				writeError(w, http.StatusNotFound, "NOT_FOUND", "transfer not found")
				return
			}
			if errors.Is(err, transfer.ErrChunkMismatch) {
				writeError(w, http.StatusConflict, "CHUNK_HASH_MISMATCH", err.Error())
				return
			}
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// --------- POST /transfers/{id}/complete ---------

func completeTransferHandler(tm *transfer.Manager, ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := chi.URLParam(r, "id")
		_, targetPath, err := tm.Complete(id)
		if err != nil {
			if errors.Is(err, transfer.ErrNotFound) {
				writeError(w, http.StatusNotFound, "NOT_FOUND", "transfer not found")
				return
			}
			if errors.Is(err, transfer.ErrFileMismatch) {
				writeError(w, http.StatusUnprocessableEntity, "HASH_MISMATCH", err.Error())
				return
			}
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		entry, err := ops.Meta(targetPath)
		if err != nil {
			// Transfer succeeded but meta failed — return a minimal entry.
			writeJSON(w, http.StatusOK, map[string]any{
				"path":     targetPath,
				"modified": time.Now(),
			})
			return
		}
		writeJSON(w, http.StatusOK, entry)
	}
}

// transferSession converts a store.Transfer to the UploadSession JSON shape.
func transferSession(t *store.Transfer) map[string]any {
	chunks := t.ReceivedChunks
	if chunks == nil {
		chunks = []int{}
	}
	return map[string]any{
		"id":             t.ID,
		"path":           t.TargetPath,
		"size":           t.TotalSize,
		"chunkSize":      t.ChunkSize,
		"totalChunks":    t.TotalChunks,
		"receivedChunks": chunks,
		"status":         t.Status,
	}
}
