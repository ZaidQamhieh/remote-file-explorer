// Package server — archive peek handler (list contents without extracting).
package server

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
)

// ArchiveEntry represents a single entry inside an archive.
type ArchiveEntry struct {
	Path     string    `json:"path"`
	Size     int64     `json:"size"`
	Modified time.Time `json:"modified"`
	IsDir    bool      `json:"isDir"`
}

func archivePeekHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
		path := r.URL.Query().Get("path")
		if path == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "path query param required")
			return
		}

		limit := 500
		if l := r.URL.Query().Get("limit"); l != "" {
			if n, err := strconv.Atoi(l); err == nil && n > 0 {
				limit = n
			}
		}

		resolved, err := ops.Resolve(path)
		if err != nil {
			handleFsError(w, err)
			return
		}

		if _, err := os.Stat(resolved); err != nil {
			if os.IsNotExist(err) {
				handleFsError(w, fsops.ErrNotFound)
				return
			}
			writeInternal(w, "archive stat", err)
			return
		}

		var entries []ArchiveEntry
		lower := strings.ToLower(resolved)
		switch {
		case strings.HasSuffix(lower, ".zip"):
			entries, err = peekZip(resolved, limit)
		case strings.HasSuffix(lower, ".tar.gz"), strings.HasSuffix(lower, ".tgz"):
			entries, err = peekTarGz(resolved, limit)
		case strings.HasSuffix(lower, ".tar"):
			entries, err = peekTar(resolved, limit)
		default:
			handleFsError(w, fsops.ErrUnsupported)
			return
		}
		if err != nil {
			writeInternal(w, "archive peek", err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"entries": entries})
	}
}

func peekZip(path string, limit int) ([]ArchiveEntry, error) {
	zr, err := zip.OpenReader(path)
	if err != nil {
		return nil, err
	}
	defer zr.Close()

	entries := make([]ArchiveEntry, 0, min(len(zr.File), limit))
	for i, f := range zr.File {
		if i >= limit {
			break
		}
		entries = append(entries, ArchiveEntry{
			Path:     f.Name,
			Size:     int64(f.UncompressedSize64),
			Modified: f.Modified,
			IsDir:    f.FileInfo().IsDir(),
		})
	}
	return entries, nil
}

func peekTarGz(path string, limit int) ([]ArchiveEntry, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	gz, err := gzip.NewReader(f)
	if err != nil {
		return nil, err
	}
	defer gz.Close()

	return readTarEntries(tar.NewReader(gz), limit)
}

func peekTar(path string, limit int) ([]ArchiveEntry, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	return readTarEntries(tar.NewReader(f), limit)
}

func readTarEntries(tr *tar.Reader, limit int) ([]ArchiveEntry, error) {
	var entries []ArchiveEntry
	for len(entries) < limit {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		entries = append(entries, ArchiveEntry{
			Path:     hdr.Name,
			Size:     hdr.Size,
			Modified: hdr.ModTime,
			IsDir:    hdr.Typeflag == tar.TypeDir,
		})
	}
	return entries, nil
}
