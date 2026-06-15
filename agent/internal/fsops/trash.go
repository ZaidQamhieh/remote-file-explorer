// Package fsops — trash (move-to-trash / restore) operations.
//
// The store follows the XDG Trash layout: a `files/` directory holding the
// trashed items and an `info/` directory holding one `<id>.trashinfo` sidecar
// per item recording its original path and deletion time, so items can be
// restored to where they came from. On Linux the store lives in the user's
// real desktop trash (`~/.local/share/Trash`), so app-side deletes show up in
// the desktop's Trash too; on other platforms it falls back to a managed
// directory under the agent data dir.
//
// User-facing paths (the thing being trashed, and a restore destination) go
// through Resolve so the path jail + read-only flag apply; the store itself is
// agent-managed and not jail-checked.
package fsops

import (
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"
)

// TrashEntry describes one item in the trash store.
type TrashEntry struct {
	ID           string    `json:"id"` // unique key = basename under files/
	Name         string    `json:"name"`
	OriginalPath string    `json:"originalPath"`
	DeletedAt    time.Time `json:"deletedAt"`
	Size         int64     `json:"size"`
	IsDir        bool      `json:"isDir"`
}

const trashInfoExt = ".trashinfo"

// xdgDeletionDate is the XDG trashinfo DeletionDate layout (local time, no zone).
const xdgDeletionDate = "2006-01-02T15:04:05"

func trashFilesDir(trashDir string) string { return filepath.Join(trashDir, "files") }
func trashInfoDir(trashDir string) string  { return filepath.Join(trashDir, "info") }

// MoveToTrash moves each path into the trash store at trashDir, writing a
// .trashinfo sidecar so it can be restored. Each path is jail-checked via
// Resolve. Cross-filesystem moves fall back to copy+remove. Returns a
// per-path BatchResult, mirroring Delete/Copy/Move.
func (o *Ops) MoveToTrash(paths []string, trashDir string) []BatchResult {
	if o.settings.IsReadOnly() {
		return readOnlyResults(paths)
	}
	if err := os.MkdirAll(trashFilesDir(trashDir), 0o700); err != nil {
		return errResults(paths, "TRASH_FAILED", err)
	}
	if err := os.MkdirAll(trashInfoDir(trashDir), 0o700); err != nil {
		return errResults(paths, "TRASH_FAILED", err)
	}

	results := make([]BatchResult, len(paths))
	for i, p := range paths {
		resolved, err := o.Resolve(p)
		if err != nil {
			results[i] = BatchResult{Path: p, Error: apiErr("FORBIDDEN", err.Error())}
			continue
		}
		if _, err := os.Lstat(resolved); err != nil {
			if os.IsNotExist(err) {
				results[i] = BatchResult{Path: p, Error: apiErr("PATH_NOT_FOUND", err.Error())}
			} else {
				results[i] = BatchResult{Path: p, Error: apiErr("TRASH_FAILED", err.Error())}
			}
			continue
		}

		id := uniqueTrashName(trashDir, filepath.Base(resolved))
		dest := filepath.Join(trashFilesDir(trashDir), id)
		if err := moveOrCopy(resolved, dest); err != nil {
			results[i] = BatchResult{Path: p, Error: apiErr("TRASH_FAILED", err.Error())}
			continue
		}
		if err := writeTrashInfo(trashDir, id, resolved); err != nil {
			// Roll the file back so a sidecar failure doesn't orphan the data.
			_ = moveOrCopy(dest, resolved)
			results[i] = BatchResult{Path: p, Error: apiErr("TRASH_FAILED", err.Error())}
			continue
		}
		results[i] = BatchResult{Path: p, OK: true}
	}
	return results
}

// ListTrash enumerates the trash store, newest deletion first. A missing
// store is reported as empty, not an error.
func ListTrash(trashDir string) ([]TrashEntry, error) {
	ents, err := os.ReadDir(trashInfoDir(trashDir))
	if err != nil {
		if os.IsNotExist(err) {
			return []TrashEntry{}, nil
		}
		return nil, err
	}
	out := make([]TrashEntry, 0, len(ents))
	for _, e := range ents {
		if e.IsDir() || !strings.HasSuffix(e.Name(), trashInfoExt) {
			continue
		}
		id := strings.TrimSuffix(e.Name(), trashInfoExt)
		orig, delAt, err := readTrashInfo(filepath.Join(trashInfoDir(trashDir), e.Name()))
		if err != nil {
			continue // skip malformed sidecars rather than failing the whole list
		}
		var size int64
		var isDir bool
		if fi, statErr := os.Lstat(filepath.Join(trashFilesDir(trashDir), id)); statErr == nil {
			size = fi.Size()
			isDir = fi.IsDir()
		}
		out = append(out, TrashEntry{
			ID:           id,
			Name:         filepath.Base(orig),
			OriginalPath: orig,
			DeletedAt:    delAt,
			Size:         size,
			IsDir:        isDir,
		})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].DeletedAt.After(out[j].DeletedAt) })
	return out, nil
}

// RestoreFromTrash moves each id back to its recorded original path (jail-
// checked via Resolve). If the original location is now occupied the restore
// is auto-renamed ("keep both") rather than clobbering. Returns a per-id
// BatchResult whose Path is the restored location on success.
func (o *Ops) RestoreFromTrash(ids []string, trashDir string) []BatchResult {
	if o.settings.IsReadOnly() {
		return readOnlyResults(ids)
	}
	results := make([]BatchResult, len(ids))
	for i, id := range ids {
		infoPath := filepath.Join(trashInfoDir(trashDir), id+trashInfoExt)
		orig, _, err := readTrashInfo(infoPath)
		if err != nil {
			results[i] = BatchResult{Path: id, Error: apiErr("PATH_NOT_FOUND", "no such trash item")}
			continue
		}
		dest, err := o.Resolve(orig)
		if err != nil {
			results[i] = BatchResult{Path: id, Error: apiErr("FORBIDDEN", err.Error())}
			continue
		}
		src := filepath.Join(trashFilesDir(trashDir), id)
		if _, err := os.Lstat(src); err != nil {
			results[i] = BatchResult{Path: id, Error: apiErr("PATH_NOT_FOUND", "trash payload missing")}
			continue
		}
		if _, err := os.Stat(dest); err == nil {
			dest = autoRename(dest)
		}
		if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
			results[i] = BatchResult{Path: id, Error: apiErr("RESTORE_FAILED", err.Error())}
			continue
		}
		if err := moveOrCopy(src, dest); err != nil {
			results[i] = BatchResult{Path: id, Error: apiErr("RESTORE_FAILED", err.Error())}
			continue
		}
		_ = os.Remove(infoPath)
		results[i] = BatchResult{Path: dest, OK: true}
	}
	return results
}

// EmptyTrash permanently removes trash items. With no ids the whole store is
// emptied; otherwise only the given ids are removed.
func EmptyTrash(trashDir string, ids []string) error {
	if len(ids) == 0 {
		if err := os.RemoveAll(trashFilesDir(trashDir)); err != nil {
			return err
		}
		return os.RemoveAll(trashInfoDir(trashDir))
	}
	for _, id := range ids {
		if err := os.RemoveAll(filepath.Join(trashFilesDir(trashDir), id)); err != nil {
			return err
		}
		if err := os.Remove(filepath.Join(trashInfoDir(trashDir), id+trashInfoExt)); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	return nil
}

// --------- helpers ---------

func readOnlyResults(paths []string) []BatchResult {
	res := make([]BatchResult, len(paths))
	for i, p := range paths {
		res[i] = BatchResult{Path: p, Error: &Error{Code: "READ_ONLY", Message: ErrReadOnly.Error()}}
	}
	return res
}

func errResults(paths []string, code string, err error) []BatchResult {
	res := make([]BatchResult, len(paths))
	for i, p := range paths {
		res[i] = BatchResult{Path: p, Error: apiErr(code, err.Error())}
	}
	return res
}

// moveOrCopy renames src to dst, falling back to a recursive copy + remove
// when the two are on different filesystems (os.Rename returns EXDEV).
func moveOrCopy(src, dst string) error {
	err := os.Rename(src, dst)
	if err == nil {
		return nil
	}
	if !errors.Is(err, syscall.EXDEV) {
		return err
	}
	if err := copyRecursive(src, dst); err != nil {
		return err
	}
	return os.RemoveAll(src)
}

// uniqueTrashName returns a name not already used by either files/ or info/.
func uniqueTrashName(trashDir, base string) string {
	candidate := base
	ext := filepath.Ext(base)
	stem := strings.TrimSuffix(base, ext)
	for i := 1; ; i++ {
		_, e1 := os.Lstat(filepath.Join(trashFilesDir(trashDir), candidate))
		_, e2 := os.Lstat(filepath.Join(trashInfoDir(trashDir), candidate+trashInfoExt))
		if os.IsNotExist(e1) && os.IsNotExist(e2) {
			return candidate
		}
		candidate = fmt.Sprintf("%s_%d%s", stem, i, ext)
	}
}

func writeTrashInfo(trashDir, id, originalPath string) error {
	content := fmt.Sprintf(
		"[Trash Info]\nPath=%s\nDeletionDate=%s\n",
		encodeTrashPath(originalPath),
		time.Now().Format(xdgDeletionDate),
	)
	return os.WriteFile(filepath.Join(trashInfoDir(trashDir), id+trashInfoExt), []byte(content), 0o600)
}

// encodeTrashPath percent-encodes an absolute path the XDG-spec way: each path
// segment is escaped (spaces, unicode, reserved chars) but the '/' separators
// are kept literal, so a desktop file manager can also parse + restore items
// the app trashed (the store is the user's real ~/.local/share/Trash). The
// inverse is plain url.PathUnescape (used by readTrashInfo), which leaves the
// literal '/' untouched and decodes the %xx within each segment.
func encodeTrashPath(p string) string {
	parts := strings.Split(p, "/")
	for i, seg := range parts {
		parts[i] = url.PathEscape(seg)
	}
	return strings.Join(parts, "/")
}

func readTrashInfo(path string) (originalPath string, deletedAt time.Time, err error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", time.Time{}, err
	}
	for _, line := range strings.Split(string(data), "\n") {
		if v, ok := strings.CutPrefix(line, "Path="); ok {
			v = strings.TrimSpace(v)
			if dec, derr := url.PathUnescape(v); derr == nil {
				originalPath = dec
			} else {
				originalPath = v
			}
		} else if v, ok := strings.CutPrefix(line, "DeletionDate="); ok {
			deletedAt, _ = time.ParseInLocation(xdgDeletionDate, strings.TrimSpace(v), time.Local)
		}
	}
	if originalPath == "" {
		return "", time.Time{}, fmt.Errorf("malformed trashinfo: %s", path)
	}
	return originalPath, deletedAt, nil
}
