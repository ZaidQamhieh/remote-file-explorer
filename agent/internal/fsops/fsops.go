// Package fsops implements filesystem operations with a path-jail.
// Traversal attempts (../) and symlink escapes are rejected when
// allowed_root_paths is configured.
package fsops

import (
	"crypto/md5"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"hash"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// ErrForbidden is returned when a path is outside the jail.
var ErrForbidden = errors.New("path is outside allowed root")

// ErrReadOnly is returned for write operations when in read-only mode.
var ErrReadOnly = errors.New("agent is in read-only mode")

// ErrNotFound is returned when a path doesn't exist.
var ErrNotFound = errors.New("path not found")

// ErrConflict is returned when a destination already exists.
var ErrConflict = errors.New("destination already exists")

// ErrUnsupported is returned by Extract for an archive whose extension is
// not a supported format (.zip/.tar.gz/.tgz).
var ErrUnsupported = errors.New("unsupported archive format")

// ErrStale is returned by WriteContent when the on-disk file's mtime no
// longer matches the baseModified the caller last read, indicating the
// file changed since then (optimistic-concurrency conflict).
var ErrStale = errors.New("file changed since last read")

// The path-jail and access-control model (SettingsView, the read-only/jailed
// wrappers, Resolve, resolveReal, isUnder) lives in jail.go — the security
// boundary that every operation below passes through.

// Ops performs filesystem operations with an optional path jail.
type Ops struct {
	settings SettingsView
	// denyAll, when true, makes Resolve reject every path regardless of
	// settings/roots. Set only by Jailed when a device's jailRoot falls
	// outside the agent's configured roots — see Jailed for why this can't
	// simply be represented as an empty roots slice (empty roots means "no
	// jail" / allow everything).
	denyAll bool
}

// New creates an Ops with optional allowedRoots.
// If allowedRoots is empty every path is allowed.
func New(allowedRoots []string, readOnly bool) *Ops {
	roots := make([]string, 0, len(allowedRoots))
	for _, r := range allowedRoots {
		clean := filepath.Clean(r)
		if clean != "" && clean != "." {
			roots = append(roots, clean)
		}
	}
	return &Ops{settings: staticSettings{readOnly: readOnly, roots: roots}}
}

// NewWithSettings builds an Ops backed by a live SettingsView.
func NewWithSettings(v SettingsView) *Ops {
	return &Ops{settings: v}
}

// IsReadOnly reports whether writes are currently rejected. Handlers that
// mutate outside the batch Ops (e.g. chmod) must consult this so read-only
// policy is enforced uniformly (PR-04).
func (o *Ops) IsReadOnly() bool { return o.settings.IsReadOnly() }

// Roots returns the configured allowed roots (a copy). An empty slice
// means there is no jail (anything is allowed) — callers that need a
// concrete starting point in that case should fall back to something
// sensible (e.g. the user's home directory or filesystem drives).
func (o *Ops) Roots() []string {
	if o.denyAll {
		return nil
	}
	src := o.settings.Roots()
	roots := make([]string, len(src))
	copy(roots, src)
	return roots
}

// --------- Entry type ---------

// Entry is the JSON representation of a filesystem item.
type Entry struct {
	Name          string    `json:"name"`
	Path          string    `json:"path"`
	IsDir         bool      `json:"isDir"`
	Size          int64     `json:"size"`
	MimeType      string    `json:"mimeType,omitempty"`
	Mode          string    `json:"mode"`
	Modified      time.Time `json:"modified"`
	Created       time.Time `json:"created"`
	IsSymlink     bool      `json:"isSymlink"`
	SymlinkTarget string    `json:"symlinkTarget,omitempty"`
}

// Listing is a paginated directory listing.
type Listing struct {
	Path       string  `json:"path"`
	Entries    []Entry `json:"entries"`
	NextCursor *string `json:"nextCursor"`
}

// Drive represents a filesystem mount point.
type Drive struct {
	Path       string `json:"path"`
	Label      string `json:"label"`
	TotalBytes int64  `json:"totalBytes"`
	FreeBytes  int64  `json:"freeBytes"`
	IsOS       bool   `json:"isOS"`
}

// --------- ListDir ---------

// maxListLimit caps how many entries one ListDir page may return, regardless
// of the client-requested limit (PR-48).
const maxListLimit = 1000

// ListDir lists a directory with cursor-based pagination by name.
func (o *Ops) ListDir(path, cursor string, limit int) (*Listing, error) {
	resolved, err := o.access(path)
	if err != nil {
		return nil, err
	}
	defer resolved.close()
	f, err := resolved.open()
	if err != nil {
		if os.IsNotExist(err) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	defer f.Close()

	infos, err := f.Readdir(-1)
	if err != nil {
		return nil, err
	}
	sort.Slice(infos, func(i, j int) bool {
		return infos[i].Name() < infos[j].Name()
	})

	if limit <= 0 {
		limit = 200
	}
	// PR-48: bound the per-page response regardless of what the client asks,
	// so one request can't demand an enormous page. The full-directory read
	// and sort above is inherent to name-ordered pagination.
	if limit > maxListLimit {
		limit = maxListLimit
	}

	var nextCursor *string

	// Filter by cursor first (skip entries at or before the cursor).
	var filtered []os.FileInfo
	for _, info := range infos {
		if cursor != "" && info.Name() <= cursor {
			continue
		}
		filtered = append(filtered, info)
	}

	// Cap at limit; if there are more, record the last-included name as cursor.
	end := len(filtered)
	if end > limit {
		end = limit
	}
	entries := make([]Entry, 0, end)
	for _, info := range filtered[:end] {
		entries = append(entries, entryFromSecureInfo(info, resolved.child(info.Name()), true))
	}
	if end < len(filtered) {
		c := entries[end-1].Name
		nextCursor = &c
	}

	return &Listing{Path: resolved.full, Entries: entries, NextCursor: nextCursor}, nil
}

// --------- Meta ---------

// Meta returns detailed metadata for a single entry.
func (o *Ops) Meta(path string) (*Entry, error) {
	resolved, err := o.access(path)
	if err != nil {
		return nil, err
	}
	defer resolved.close()
	// Use Lstat to detect symlinks.
	info, err := resolved.lstat()
	if err != nil {
		if os.IsNotExist(err) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	e := entryFromSecureInfo(info, resolved, true)
	return &e, nil
}

// --------- Checksum ---------

// Checksum computes a hex-encoded hash of the file at path.
// Supported algorithms: "sha256" (default), "sha1", "md5".
func (o *Ops) Checksum(path, algo string) (string, error) {
	resolved, err := o.access(path)
	if err != nil {
		return "", err
	}
	defer resolved.close()
	info, err := resolved.lstat()
	if err != nil {
		if os.IsNotExist(err) {
			return "", ErrNotFound
		}
		return "", err
	}
	if info.IsDir() {
		return "", fmt.Errorf("cannot checksum a directory")
	}
	f, err := resolved.open()
	if err != nil {
		return "", err
	}
	defer f.Close()

	var h hash.Hash
	switch algo {
	case "md5":
		h = md5.New()
	case "sha1":
		h = sha1.New()
	case "", "sha256":
		h = sha256.New()
	default:
		return "", fmt.Errorf("unsupported algorithm %q (use sha256, sha1, or md5)", algo)
	}
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// --------- Drives ---------

// Drives returns the available mount points / drives.
func Drives() ([]Drive, error) {
	return platformDrives()
}

// Drives returns the mount points/drives visible through o: every drive when
// o has no configured roots (no jail — today's default, unchanged), or only
// the drives that contain or are contained by one of o's roots otherwise
// (PR-61: a per-device jail must narrow /system/drives the same way it
// narrows every other listing, instead of always exposing the full host
// topology regardless of jail).
func (o *Ops) Drives() ([]Drive, error) {
	if o.IsDenyAll() {
		// Roots() intentionally returns an empty slice for denyAll, but the
		// generic empty-roots behavior below means "no jail". Keep these
		// states separate so an invalid per-device jail cannot expose the
		// host's drive topology.
		return []Drive{}, nil
	}
	all, err := platformDrives()
	if err != nil {
		return nil, err
	}
	return filterDrivesByRoots(all, o.Roots()), nil
}

// filterDrivesByRoots keeps only the drives at or nested within one of roots;
// roots empty (no jail) returns all unchanged. A jailed Ops's entire browsable
// surface is exactly its root(s) (see Jailed) — a drive the jail root sits
// *inside* of (an ancestor mount) can never actually be browsed to, so
// listing it would only leak that it exists; a drive nested *inside* the
// jail (e.g. a second filesystem mounted under it) is real and reachable, so
// it stays. Split out from Drives so the filtering logic is testable without
// a real platformDrives().
func filterDrivesByRoots(all []Drive, roots []string) []Drive {
	if len(roots) == 0 {
		return all
	}
	filtered := make([]Drive, 0, len(all))
	for _, d := range all {
		for _, root := range roots {
			if isUnder(d.Path, root) {
				filtered = append(filtered, d)
				break
			}
		}
	}
	return filtered
}

// --------- Create ---------

// CreateFolder creates a directory (and parents).
func (o *Ops) CreateFolder(path string) (*Entry, error) {
	if o.settings.IsReadOnly() {
		return nil, ErrReadOnly
	}
	resolved, err := o.access(path)
	if err != nil {
		return nil, err
	}
	defer resolved.close()
	if _, err := resolved.stat(); err == nil {
		return nil, ErrConflict
	}
	if err := resolved.mkdirAll(0o755); err != nil {
		return nil, err
	}
	return o.Meta(resolved.full)
}

// CreateFile creates an empty file (creates parent dirs as needed).
func (o *Ops) CreateFile(path string) (*Entry, error) {
	if o.settings.IsReadOnly() {
		return nil, ErrReadOnly
	}
	resolved, err := o.access(path)
	if err != nil {
		return nil, err
	}
	defer resolved.close()
	if _, err := resolved.stat(); err == nil {
		return nil, ErrConflict
	}
	parent := resolved.parent()
	if err := parent.mkdirAll(0o755); err != nil {
		return nil, err
	}
	f, err := resolved.openFile(os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o644)
	if err != nil {
		return nil, err
	}
	if err := f.Close(); err != nil {
		return nil, err
	}
	return o.Meta(resolved.full)
}

// --------- WriteContent ---------

// WriteContent writes (or replaces) the content of a file at path with data,
// atomically. If baseModified is non-nil, the existing file's mtime
// (truncated to the second) must match baseModified (also truncated to the
// second) or ErrStale is returned — this gives the caller optimistic
// concurrency: a write based on a stale read is rejected instead of silently
// clobbering newer content.
//
// The write is performed by creating a temp file in the same directory as
// the target, writing+fsyncing it, then renaming it over the target. If the
// target already exists its file mode is preserved; otherwise the new file
// is created with mode 0644.
func (o *Ops) WriteContent(path string, data []byte, baseModified *time.Time) (*Entry, error) {
	if o.settings.IsReadOnly() {
		return nil, ErrReadOnly
	}
	resolved, err := o.access(path)
	if err != nil {
		return nil, err
	}
	defer resolved.close()

	mode := os.FileMode(0o644)
	if baseModified != nil {
		info, statErr := resolved.stat()
		if statErr != nil {
			if os.IsNotExist(statErr) {
				return nil, ErrNotFound
			}
			return nil, statErr
		}
		if !info.ModTime().Truncate(time.Second).Equal(baseModified.Truncate(time.Second)) {
			return nil, ErrStale
		}
		mode = info.Mode()
	} else if info, statErr := resolved.stat(); statErr == nil {
		mode = info.Mode()
	} else if !os.IsNotExist(statErr) {
		return nil, statErr
	}

	if err := resolved.parent().mkdirAll(0o755); err != nil {
		return nil, err
	}

	tmpPath, tmp, err := resolved.createTemp("." + filepath.Base(resolved.full) + ".rfe-tmp-*")
	if err != nil {
		return nil, err
	}
	cleanup := func() {
		_ = tmpPath.remove()
	}

	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		cleanup()
		return nil, err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		cleanup()
		return nil, err
	}
	if err := tmp.Chmod(mode); err != nil {
		tmp.Close()
		cleanup()
		return nil, err
	}
	if err := tmp.Close(); err != nil {
		cleanup()
		return nil, err
	}
	if err := tmpPath.renameTo(resolved); err != nil {
		cleanup()
		return nil, err
	}

	return o.Meta(resolved.full)
}

// --------- Rename ---------

// Rename moves src to dst.
func (o *Ops) Rename(src, dst string) (*Entry, error) {
	if o.settings.IsReadOnly() {
		return nil, ErrReadOnly
	}
	// dst might not exist yet; Resolve handles non-existent paths by
	// resolving symlinks on the deepest existing ancestor.
	resSrc, resDst, err := o.accessPair(src, dst)
	if err != nil {
		return nil, err
	}
	defer resSrc.close()
	if resDst.root != resSrc.root {
		defer resDst.close()
	}
	if err := resDst.parent().mkdirAll(0o755); err != nil {
		return nil, err
	}
	if err := resSrc.renameTo(resDst); err != nil {
		if resSrc.root != resDst.root {
			err = moveAcrossRootsSecure(resSrc, resDst)
		}
		if err != nil {
			return nil, err
		}
	}
	return o.Meta(resDst.full)
}

// --------- Copy ---------

// BatchResult is the per-source outcome of a batch Copy/Move/Delete.
type BatchResult struct {
	Path  string `json:"path"`
	OK    bool   `json:"ok"`
	Error *Error `json:"error,omitempty"`
}

// Error is the JSON error envelope from the contract.
type Error struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// Copy copies sources into destDir.
//
// Per-source destination collisions are resolved by precedence:
//  1. duplicate=true: auto-rename the destination (keep-both); overwrite is
//     ignored in this case.
//  2. else overwrite=true: replace the existing destination (remove it, then
//     copy the source over it).
//  3. else: a CONFLICT BatchResult for that source (unchanged).
//
// Two guards apply regardless of duplicate/overwrite, to avoid destroying
// data:
//   - If the resolved source and computed destination are the same path, the
//     copy is a no-op (reported as OK) rather than removing-then-copying a
//     path onto itself.
//   - The destination is never removed if it is an ancestor of (or equal to)
//     the source, since deleting it would delete the source itself; this
//     falls back to a CONFLICT result.
func (o *Ops) Copy(sources []string, destDir string, duplicate, overwrite bool) []BatchResult {
	if o.settings.IsReadOnly() {
		res := make([]BatchResult, len(sources))
		for i, s := range sources {
			res[i] = BatchResult{Path: s, Error: &Error{Code: "READ_ONLY", Message: ErrReadOnly.Error()}}
		}
		return res
	}
	results := make([]BatchResult, len(sources))
	for i, src := range sources {
		resSrc, dstDir, err := o.accessPair(src, destDir)
		if err != nil {
			results[i] = BatchResult{Path: src, Error: apiErr("FORBIDDEN", err.Error())}
			continue
		}
		dst := dstDir.child(filepath.Base(resSrc.full))

		// Same-path guard: copying a path onto itself is a no-op — UNLESS
		// duplicate is requested, in which case copying into the source's own
		// directory means "make a renamed copy" (duplicate-in-place), handled
		// by the auto-rename below.
		if resSrc.full == dst.full && !duplicate {
			results[i] = BatchResult{Path: src, OK: true}
			resSrc.close()
			if dstDir.root != resSrc.root {
				dstDir.close()
			}
			continue
		}

		if _, err := dst.stat(); err == nil {
			switch {
			case duplicate:
				dst = autoRenameSecure(dst)
			case overwrite:
				// Ancestor guard: never remove a destination that contains
				// the source — that would delete the source itself.
				if isUnder(resSrc.full, dst.full) {
					results[i] = BatchResult{Path: src, Error: apiErr("CONFLICT", "destination already exists")}
					resSrc.close()
					if dstDir.root != resSrc.root {
						dstDir.close()
					}
					continue
				}
				if err := dst.removeAll(); err != nil {
					results[i] = BatchResult{Path: src, Error: apiErr("COPY_FAILED", err.Error())}
					resSrc.close()
					if dstDir.root != resSrc.root {
						dstDir.close()
					}
					continue
				}
			default:
				results[i] = BatchResult{Path: src, Error: apiErr("CONFLICT", "destination already exists")}
				resSrc.close()
				if dstDir.root != resSrc.root {
					dstDir.close()
				}
				continue
			}
		}
		if err := copySecureRecursive(resSrc, dst); err != nil {
			results[i] = BatchResult{Path: src, Error: apiErr("COPY_FAILED", err.Error())}
		} else {
			results[i] = BatchResult{Path: src, OK: true}
		}
		resSrc.close()
		if dstDir.root != resSrc.root {
			dstDir.close()
		}
	}
	return results
}

// Move moves sources into destDir (batch).
//
// Per-source destination collisions follow the same precedence as Copy:
// duplicate (auto-rename) wins, else overwrite replaces the existing
// destination (os.RemoveAll then os.Rename), else CONFLICT. The same
// same-path and ancestor guards apply (see Copy).
func (o *Ops) Move(sources []string, destDir string, duplicate, overwrite bool) []BatchResult {
	if o.settings.IsReadOnly() {
		res := make([]BatchResult, len(sources))
		for i, s := range sources {
			res[i] = BatchResult{Path: s, Error: &Error{Code: "READ_ONLY", Message: ErrReadOnly.Error()}}
		}
		return res
	}
	results := make([]BatchResult, len(sources))
	for i, src := range sources {
		resSrc, dstDir, err := o.accessPair(src, destDir)
		if err != nil {
			results[i] = BatchResult{Path: src, Error: apiErr("FORBIDDEN", err.Error())}
			continue
		}
		dst := dstDir.child(filepath.Base(resSrc.full))

		// Same-path guard: moving a path onto itself is a no-op.
		if resSrc.full == dst.full {
			results[i] = BatchResult{Path: src, OK: true}
			resSrc.close()
			if dstDir.root != resSrc.root {
				dstDir.close()
			}
			continue
		}

		if _, err := dst.stat(); err == nil {
			switch {
			case duplicate:
				dst = autoRenameSecure(dst)
			case overwrite:
				// Ancestor guard: never remove a destination that contains
				// the source — that would delete the source itself.
				if isUnder(resSrc.full, dst.full) {
					results[i] = BatchResult{Path: src, Error: apiErr("CONFLICT", "destination already exists")}
					resSrc.close()
					if dstDir.root != resSrc.root {
						dstDir.close()
					}
					continue
				}
				if err := dst.removeAll(); err != nil {
					results[i] = BatchResult{Path: src, Error: apiErr("MOVE_FAILED", err.Error())}
					resSrc.close()
					if dstDir.root != resSrc.root {
						dstDir.close()
					}
					continue
				}
			default:
				results[i] = BatchResult{Path: src, Error: apiErr("CONFLICT", "destination already exists")}
				resSrc.close()
				if dstDir.root != resSrc.root {
					dstDir.close()
				}
				continue
			}
		}
		if err := dstDir.mkdirAll(0o755); err != nil {
			results[i] = BatchResult{Path: src, Error: apiErr("MOVE_FAILED", err.Error())}
			resSrc.close()
			if dstDir.root != resSrc.root {
				dstDir.close()
			}
			continue
		}
		if err := resSrc.renameTo(dst); err != nil {
			if resSrc.root != dst.root {
				err = moveAcrossRootsSecure(resSrc, dst)
			}
			if err != nil {
				results[i] = BatchResult{Path: src, Error: apiErr("MOVE_FAILED", err.Error())}
			} else {
				results[i] = BatchResult{Path: src, OK: true}
			}
		} else {
			results[i] = BatchResult{Path: src, OK: true}
		}
		resSrc.close()
		if dstDir.root != resSrc.root {
			dstDir.close()
		}
	}
	return results
}

// Delete deletes one or more paths.
func (o *Ops) Delete(paths []string) []BatchResult {
	if o.settings.IsReadOnly() {
		res := make([]BatchResult, len(paths))
		for i, p := range paths {
			res[i] = BatchResult{Path: p, Error: &Error{Code: "READ_ONLY", Message: ErrReadOnly.Error()}}
		}
		return res
	}
	results := make([]BatchResult, len(paths))
	for i, p := range paths {
		resolved, err := o.access(p)
		if err != nil {
			results[i] = BatchResult{Path: p, Error: apiErr("FORBIDDEN", err.Error())}
			continue
		}
		if err := resolved.removeAll(); err != nil {
			results[i] = BatchResult{Path: p, Error: apiErr("DELETE_FAILED", err.Error())}
		} else {
			results[i] = BatchResult{Path: p, OK: true}
		}
		resolved.close()
	}
	return results
}

// --------- helpers ---------

// EntryFromInfo builds an Entry from a FileInfo and its full resolved path,
// using the same name/size/mime/mode/timestamp logic as ListDir and Meta.
// Exported so other packages (e.g. the search handler) can build Entry
// values consistently while walking the tree themselves.
func EntryFromInfo(info os.FileInfo, fullPath string) Entry {
	return entryFromInfo(info, fullPath, true)
}

// EntryFromInfoNoSniff is EntryFromInfo without content sniffing: the MIME
// type comes from the extension alone, and an extensionless file reports
// "application/octet-stream" instead of being opened and read.
//
// For one entry the sniff is nothing; for the search index it is the whole
// cost model. That walk visits every file under the roots on every rebuild,
// so sniffing turns a directory walk into an open+read storm across the tree
// (PR-47). Callers showing a single entry should use EntryFromInfo.
func EntryFromInfoNoSniff(info os.FileInfo, fullPath string) Entry {
	return entryFromInfo(info, fullPath, false)
}

func entryFromInfo(info os.FileInfo, fullPath string, sniff bool) Entry {
	isSymlink := info.Mode()&os.ModeSymlink != 0
	// info comes from Lstat/Readdir, which never follows symlinks — a symlink
	// to a directory would otherwise report IsDir=false and become permanently
	// unnavigable in the UI. Stat (follows) to get the real target type;
	// a broken link falls back to the symlink's own (non-dir) info.
	isDir := info.IsDir()
	if isSymlink {
		if target, err := os.Stat(fullPath); err == nil {
			isDir = target.IsDir()
		}
	}
	mtype := ""
	if !isDir {
		mtype = mimeForPath(fullPath, info, sniff)
	}
	e := Entry{
		Name:      info.Name(),
		Path:      fullPath,
		IsDir:     isDir,
		Size:      info.Size(),
		MimeType:  mtype,
		Mode:      info.Mode().String(),
		Modified:  info.ModTime(),
		Created:   birthTime(info),
		IsSymlink: isSymlink,
	}
	if isSymlink {
		if target, err := os.Readlink(fullPath); err == nil {
			e.SymlinkTarget = target
		}
	}
	return e
}

// entryFromSecureInfo mirrors entryFromInfo while opening the item relative to
// an already-open jail root. Directory listings use this variant so a link
// swapped between Readdir and metadata/sniffing cannot redirect a read outside
// the jail.
func entryFromSecureInfo(info os.FileInfo, path *securePath, sniff bool) Entry {
	isSymlink := info.Mode()&os.ModeSymlink != 0
	isDir := info.IsDir()
	if isSymlink {
		if target, err := path.stat(); err == nil {
			isDir = target.IsDir()
		}
	}
	mtype := ""
	if !isDir {
		mtype = mimeForSecurePath(path, info, sniff)
	}
	e := Entry{
		Name:      info.Name(),
		Path:      path.full,
		IsDir:     isDir,
		Size:      info.Size(),
		MimeType:  mtype,
		Mode:      info.Mode().String(),
		Modified:  info.ModTime(),
		Created:   birthTime(info),
		IsSymlink: isSymlink,
	}
	if isSymlink {
		if target, err := path.readlink(); err == nil {
			e.SymlinkTarget = target
		}
	}
	return e
}

func mimeForSecurePath(path *securePath, info os.FileInfo, sniff bool) string {
	if ext := filepath.Ext(path.full); ext != "" {
		if m := mime.TypeByExtension(ext); m != "" {
			return m
		}
	}
	if sniff && info.Size() > 0 && !info.IsDir() {
		f, err := path.open()
		if err == nil {
			defer f.Close()
			buf := make([]byte, 512)
			n, _ := f.Read(buf)
			if n > 0 {
				return http.DetectContentType(buf[:n])
			}
		}
	}
	return "application/octet-stream"
}

func mimeForPath(path string, info os.FileInfo, sniff bool) string {
	// First try extension.
	if ext := filepath.Ext(path); ext != "" {
		if m := mime.TypeByExtension(ext); m != "" {
			return m
		}
	}
	// Sniff up to 512 bytes.
	if sniff && info.Size() > 0 && !info.IsDir() {
		f, err := os.Open(path)
		if err == nil {
			defer f.Close()
			buf := make([]byte, 512)
			n, _ := f.Read(buf)
			if n > 0 {
				return http.DetectContentType(buf[:n])
			}
		}
	}
	return "application/octet-stream"
}

func autoRenameSecure(dst *securePath) *securePath {
	dir := dst.parent()
	base := filepath.Base(dst.full)
	ext := filepath.Ext(base)
	stem := strings.TrimSuffix(base, ext)
	for i := 1; ; i++ {
		candidate := dir.child(fmt.Sprintf("%s (%d)%s", stem, i, ext))
		if _, err := candidate.lstat(); os.IsNotExist(err) {
			return candidate
		}
	}
}

// copySecureRecursive copies a tree using path operations rooted at each
// source/destination jail handle. It recreates symlinks without dereferencing
// them and uses exclusive create after removing a destination symlink, so a
// concurrent link swap cannot redirect a write outside the destination root.
func copySecureRecursive(src, dst *securePath) error {
	info, err := src.lstat()
	if err != nil {
		return err
	}
	if info.Mode()&os.ModeSymlink != 0 {
		target, err := src.readlink()
		if err != nil {
			return err
		}
		if err := dst.parent().mkdirAll(0o755); err != nil {
			return err
		}
		if err := dst.remove(); err != nil && !os.IsNotExist(err) {
			return err
		}
		if dst.root != nil {
			return dst.root.Symlink(target, dst.name)
		}
		return os.Symlink(target, dst.full)
	}
	if info.IsDir() {
		if err := dst.mkdirAll(info.Mode().Perm()); err != nil {
			return err
		}
		dir, err := src.open()
		if err != nil {
			return err
		}
		entries, readErr := dir.Readdir(-1)
		closeErr := dir.Close()
		if readErr != nil {
			return readErr
		}
		if closeErr != nil {
			return closeErr
		}
		for _, entry := range entries {
			if err := copySecureRecursive(src.child(entry.Name()), dst.child(entry.Name())); err != nil {
				return err
			}
		}
		return nil
	}
	in, err := src.open()
	if err != nil {
		return err
	}
	defer in.Close()
	if err := dst.parent().mkdirAll(0o755); err != nil {
		return err
	}
	flag := os.O_CREATE | os.O_TRUNC | os.O_WRONLY
	if fi, err := dst.lstat(); err == nil {
		if fi.Mode()&os.ModeSymlink != 0 {
			if err := dst.remove(); err != nil {
				return err
			}
			flag = os.O_CREATE | os.O_EXCL | os.O_WRONLY
		}
	} else if os.IsNotExist(err) {
		flag = os.O_CREATE | os.O_EXCL | os.O_WRONLY
	} else {
		return err
	}
	out, err := dst.openFile(flag, info.Mode())
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(out, in)
	closeErr := out.Close()
	if copyErr != nil {
		return copyErr
	}
	return closeErr
}

func apiErr(code, msg string) *Error {
	return &Error{Code: code, Message: msg}
}
