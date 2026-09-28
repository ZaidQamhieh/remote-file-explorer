// Package server — archive peek handler (list contents without extracting).
package server

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"errors"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"syscall"
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

		f, err := ops.OpenFile(resolved, os.O_RDONLY|syscall.O_NONBLOCK, 0)
		if err != nil {
			if errors.Is(err, fsops.ErrForbidden) {
				handleFsError(w, err)
			} else if os.IsNotExist(err) {
				handleFsError(w, fsops.ErrNotFound)
			} else {
				writeInternal(w, "archive open", err)
			}
			return
		}
		defer f.Close()
		info, err := f.Stat()
		if err != nil {
			writeInternal(w, "archive stat", err)
			return
		}
		if !info.Mode().IsRegular() {
			handleFsError(w, fsops.ErrUnsupported)
			return
		}

		var entries []ArchiveEntry
		lower := strings.ToLower(resolved)
		switch {
		case strings.HasSuffix(lower, ".zip"):
			entries, err = peekZipFile(f, limit)
		case strings.HasSuffix(lower, ".tar.gz"), strings.HasSuffix(lower, ".tgz"):
			entries, err = peekTarGzFile(f, limit)
		case strings.HasSuffix(lower, ".tar"):
			entries, err = peekTarFile(f, limit)
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

func peekZipFile(file *os.File, limit int) ([]ArchiveEntry, error) {
	info, err := file.Stat()
	if err != nil {
		return nil, err
	}
	zr, err := zip.NewReader(file, info.Size())
	if err != nil {
		return nil, err
	}

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

func peekTarGzFile(file *os.File, limit int) ([]ArchiveEntry, error) {
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return nil, err
	}
	gz, err := gzip.NewReader(file)
	if err != nil {
		return nil, err
	}
	defer gz.Close()

	return readTarEntries(tar.NewReader(gz), limit)
}

func peekTarFile(file *os.File, limit int) ([]ArchiveEntry, error) {
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return nil, err
	}
	return readTarEntries(tar.NewReader(file), limit)
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
