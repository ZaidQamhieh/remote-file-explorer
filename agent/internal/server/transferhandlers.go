// Package server — transfer (upload) + content (download) handlers.
package server

import (
	"compress/gzip"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/settings"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/transfer"
)

// compressibleExtensions are the (lowercase, dot-free) file extensions
// eligible for opt-in gzip-on-download (S3). Deliberately a small text/code
// allowlist — anything already compressed (zip/jpg/mp4/...) or not in this
// list is served as-is. Not the search package's categoryExtensions: that
// table is image/video/audio/document/archive *display* categories (and
// includes already-compressed formats like pdf/docx), not a
// compresses-well-with-gzip allowlist.
var compressibleExtensions = map[string]bool{
	"txt": true, "log": true, "md": true, "json": true, "yaml": true,
	"yml": true, "csv": true, "xml": true, "html": true, "css": true,
	"js": true, "go": true, "dart": true, "py": true, "java": true,
	"c": true, "cpp": true, "h": true, "sql": true,
}

// compressMinBytes is the floor below which gzip overhead isn't worth it.
const compressMinBytes = 1024

// --------- /content GET ---------

func downloadHandler(ops *fsops.Ops, st ...*settings.Store) http.HandlerFunc {
	var ss *settings.Store
	if len(st) > 0 {
		ss = st[0]
	}
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
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

		// Apply download bandwidth throttle if configured.
		var content io.ReadSeeker = f
		if ss != nil {
			if limit := ss.MaxDownloadBytesPerSec(); limit > 0 {
				content = transfer.NewThrottledReadSeeker(f, limit)
			}
		}

		// Gzip-on-download (S3): only for a fresh, non-ranged request whose
		// client opted in via Accept-Encoding, on a compressible extension
		// above the size floor. Gzip and Range don't compose — a gzip'd
		// stream's offsets don't correspond to the original file's byte
		// offsets — so any Range header unconditionally falls through to the
		// plain http.ServeContent path below, which is what makes resumable
		// download (agent_client.dart's downloadFile) safe.
		if r.Header.Get("Range") == "" &&
			acceptsGzip(r) &&
			compressibleExtensions[extOfName(info.Name())] &&
			info.Size() >= compressMinBytes {
			w.Header().Set("Content-Type", contentTypeForName(info.Name()))
			w.Header().Set("Content-Encoding", "gzip")
			w.Header().Set("Vary", "Accept-Encoding")
			gz := gzip.NewWriter(w)
			defer gz.Close()
			_, _ = io.Copy(gz, content) // best-effort stream; client sees a truncated body on error
			return
		}

		// http.ServeContent handles Range, 206, 416, Content-Type, ETag, etc.
		http.ServeContent(w, r, info.Name(), info.ModTime(), content)
	}
}

// acceptsGzip reports whether the request's Accept-Encoding header lists gzip.
func acceptsGzip(r *http.Request) bool {
	for _, enc := range strings.Split(r.Header.Get("Accept-Encoding"), ",") {
		if strings.EqualFold(strings.TrimSpace(enc), "gzip") {
			return true
		}
	}
	return false
}

// contentTypeForName returns the same MIME type http.ServeContent would have
// detected from the file extension, falling back to application/octet-stream.
func contentTypeForName(name string) string {
	if m := mime.TypeByExtension(filepath.Ext(name)); m != "" {
		return m
	}
	return "application/octet-stream"
}

// MaxContentBytes caps the size of a PUT /v1/content request body.
const MaxContentBytes int64 = 5 << 20 // 5 MiB

// --------- /content PUT ---------

func writeContentHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
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
		ops := opsFromContext(r.Context(), ops)
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

func uploadChunkHandler(tm *transfer.Manager, st ...*settings.Store) http.HandlerFunc {
	var ss *settings.Store
	if len(st) > 0 {
		ss = st[0]
	}
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

		// Apply upload bandwidth throttle if configured.
		var bodyReader io.Reader = r.Body
		if ss != nil {
			if limit := ss.MaxUploadBytesPerSec(); limit > 0 {
				bodyReader = transfer.NewThrottledReader(bodyReader, limit)
			}
		}

		data, err := io.ReadAll(bodyReader)
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
		ops := opsFromContext(r.Context(), ops)
		id := chi.URLParam(r, "id")

		// Re-check the session's target path against the calling device's
		// jail before completing. The path was already validated against the
		// jail in effect at /transfers (POST) time, but a transfer session
		// isn't otherwise scoped to the device that opened it — so a jailed
		// device must not be able to "complete" (i.e. trigger the final
		// rename for) a session targeting a path outside its own jail.
		var verifiedSHA256 string
		if t, err := tm.Status(id); err == nil && t != nil {
			verifiedSHA256 = t.SHA256
			if _, resolveErr := ops.Resolve(t.TargetPath); resolveErr != nil {
				handleFsError(w, resolveErr)
				return
			}
		}

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
		// Complete() only returns successfully once the whole-file SHA-256 has
		// been verified against t.SHA256 (captured above), so it's safe to
		// report that hash back to the client as the verified checksum.
		entry, err := ops.Meta(targetPath)
		if err != nil {
			// Transfer succeeded but meta failed — return a minimal entry.
			writeJSON(w, http.StatusOK, map[string]any{
				"path":     targetPath,
				"modified": time.Now(),
				"sha256":   verifiedSHA256,
				"verified": true,
			})
			return
		}
		// Marshal the Entry and merge in the verification fields, so the
		// response keeps all Entry fields (including omitempty behavior)
		// plus sha256/verified.
		resp := map[string]any{}
		if b, marshalErr := json.Marshal(entry); marshalErr == nil {
			_ = json.Unmarshal(b, &resp)
		}
		resp["sha256"] = verifiedSHA256
		resp["verified"] = true
		writeJSON(w, http.StatusOK, resp)
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
