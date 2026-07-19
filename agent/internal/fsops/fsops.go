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
	resolved, err := o.Resolve(path)
	if err != nil {
		return nil, err
	}
	f, err := os.Open(resolved)
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
		entries = append(entries, entryFromInfo(info, filepath.Join(resolved, info.Name()), true))
	}
	if end < len(filtered) {
		c := entries[end-1].Name
		nextCursor = &c
	}

	return &Listing{Path: resolved, Entries: entries, NextCursor: nextCursor}, nil
}

// --------- Meta ---------

// Meta returns detailed metadata for a single entry.
func (o *Ops) Meta(path string) (*Entry, error) {
	resolved, err := o.Resolve(path)
	if err != nil {
		return nil, err
	}
	// Use Lstat to detect symlinks.
	info, err := os.Lstat(resolved)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	e := entryFromInfo(info, resolved, true)
	return &e, nil
}

// --------- Checksum ---------

// Checksum computes a hex-encoded hash of the file at path.
// Supported algorithms: "sha256" (default), "sha1", "md5".
func (o *Ops) Checksum(path, algo string) (string, error) {
	resolved, err := o.Resolve(path)
	if err != nil {
		return "", err
	}
	info, err := os.Lstat(resolved)
	if err != nil {
		if os.IsNotExist(err) {
			return "", ErrNotFound
		}
		return "", err
	}
	if info.IsDir() {
		return "", fmt.Errorf("cannot checksum a directory")
	}
	f, err := os.Open(resolved)
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
	resolved, err := o.Resolve(path)
	if err != nil {
		return nil, err
	}
	if _, err := os.Stat(resolved); err == nil {
		return nil, ErrConflict
	}
	if err := os.MkdirAll(resolved, 0o755); err != nil {
		return nil, err
	}
	return o.Meta(resolved)
}

// CreateFile creates an empty file (creates parent dirs as needed).
func (o *Ops) CreateFile(path string) (*Entry, error) {
	if o.settings.IsReadOnly() {
		return nil, ErrReadOnly
	}
	resolved, err := o.Resolve(path)
	if err != nil {
		return nil, err
	}
	if _, err := os.Stat(resolved); err == nil {
		return nil, ErrConflict
	}
	if err := os.MkdirAll(filepath.Dir(resolved), 0o755); err != nil {
		return nil, err
	}
	f, err := os.Create(resolved)
	if err != nil {
		return nil, err
	}
	f.Close()
	return o.Meta(resolved)
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
	resolved, err := o.Resolve(path)
	if err != nil {
		return nil, err
	}

	mode := os.FileMode(0o644)
	if baseModified != nil {
		info, statErr := os.Stat(resolved)
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
	} else if info, statErr := os.Stat(resolved); statErr == nil {
		mode = info.Mode()
	} else if !os.IsNotExist(statErr) {
		return nil, statErr
	}

	dir := filepath.Dir(resolved)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}

	tmp, err := os.CreateTemp(dir, "."+filepath.Base(resolved)+".rfe-tmp-*")
	if err != nil {
		return nil, err
	}
	tmpName := tmp.Name()
	cleanup := func() {
		_ = os.Remove(tmpName)
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
	if err := tmp.Close(); err != nil {
		cleanup()
		return nil, err
	}
	if err := os.Chmod(tmpName, mode); err != nil {
		cleanup()
		return nil, err
	}
	if err := os.Rename(tmpName, resolved); err != nil {
		cleanup()
		return nil, err
	}

	return o.Meta(resolved)
}

// --------- Rename ---------

// Rename moves src to dst.
func (o *Ops) Rename(src, dst string) (*Entry, error) {
	if o.settings.IsReadOnly() {
		return nil, ErrReadOnly
	}
	resSrc, err := o.Resolve(src)
	if err != nil {
		return nil, err
	}
	// dst might not exist yet; Resolve handles non-existent paths by
	// resolving symlinks on the deepest existing ancestor.
	resDst, err := o.Resolve(dst)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Dir(resDst), 0o755); err != nil {
		return nil, err
	}
	if err := os.Rename(resSrc, resDst); err != nil {
		return nil, err
	}
	return o.Meta(resDst)
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
		resSrc, err := o.Resolve(src)
		if err != nil {
			results[i] = BatchResult{Path: src, Error: apiErr("FORBIDDEN", err.Error())}
			continue
		}
		dstResolved, err := o.Resolve(destDir)
		if err != nil {
			results[i] = BatchResult{Path: src, Error: apiErr("FORBIDDEN", err.Error())}
			continue
		}
		dst := filepath.Join(dstResolved, filepath.Base(resSrc))

		// Same-path guard: copying a path onto itself is a no-op — UNLESS
		// duplicate is requested, in which case copying into the source's own
		// directory means "make a renamed copy" (duplicate-in-place), handled
		// by the auto-rename below.
		if resSrc == dst && !duplicate {
			results[i] = BatchResult{Path: src, OK: true}
			continue
		}

		if _, err := os.Stat(dst); err == nil {
			switch {
			case duplicate:
				dst = autoRename(dst)
			case overwrite:
				// Ancestor guard: never remove a destination that contains
				// the source — that would delete the source itself.
				if isUnder(resSrc, dst) {
					results[i] = BatchResult{Path: src, Error: apiErr("CONFLICT", "destination already exists")}
					continue
				}
				if err := os.RemoveAll(dst); err != nil {
					results[i] = BatchResult{Path: src, Error: apiErr("COPY_FAILED", err.Error())}
					continue
				}
			default:
				results[i] = BatchResult{Path: src, Error: apiErr("CONFLICT", "destination already exists")}
				continue
			}
		}
		if err := copyRecursive(resSrc, dst); err != nil {
			results[i] = BatchResult{Path: src, Error: apiErr("COPY_FAILED", err.Error())}
		} else {
			results[i] = BatchResult{Path: src, OK: true}
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
		resSrc, err := o.Resolve(src)
		if err != nil {
			results[i] = BatchResult{Path: src, Error: apiErr("FORBIDDEN", err.Error())}
			continue
		}
		dstResolved, err := o.Resolve(destDir)
		if err != nil {
			results[i] = BatchResult{Path: src, Error: apiErr("FORBIDDEN", err.Error())}
			continue
		}
		dst := filepath.Join(dstResolved, filepath.Base(resSrc))

		// Same-path guard: moving a path onto itself is a no-op.
		if resSrc == dst {
			results[i] = BatchResult{Path: src, OK: true}
			continue
		}

		if _, err := os.Stat(dst); err == nil {
			switch {
			case duplicate:
				dst = autoRename(dst)
			case overwrite:
				// Ancestor guard: never remove a destination that contains
				// the source — that would delete the source itself.
				if isUnder(resSrc, dst) {
					results[i] = BatchResult{Path: src, Error: apiErr("CONFLICT", "destination already exists")}
					continue
				}
				if err := os.RemoveAll(dst); err != nil {
					results[i] = BatchResult{Path: src, Error: apiErr("MOVE_FAILED", err.Error())}
					continue
				}
			default:
				results[i] = BatchResult{Path: src, Error: apiErr("CONFLICT", "destination already exists")}
				continue
			}
		}
		if err := os.MkdirAll(dstResolved, 0o755); err != nil {
			results[i] = BatchResult{Path: src, Error: apiErr("MOVE_FAILED", err.Error())}
			continue
		}
		if err := os.Rename(resSrc, dst); err != nil {
			results[i] = BatchResult{Path: src, Error: apiErr("MOVE_FAILED", err.Error())}
		} else {
			results[i] = BatchResult{Path: src, OK: true}
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
		resolved, err := o.Resolve(p)
		if err != nil {
			results[i] = BatchResult{Path: p, Error: apiErr("FORBIDDEN", err.Error())}
			continue
		}
		if err := os.RemoveAll(resolved); err != nil {
			results[i] = BatchResult{Path: p, Error: apiErr("DELETE_FAILED", err.Error())}
		} else {
			results[i] = BatchResult{Path: p, OK: true}
		}
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

func autoRename(dst string) string {
	dir := filepath.Dir(dst)
	base := filepath.Base(dst)
	ext := filepath.Ext(base)
	stem := strings.TrimSuffix(base, ext)
	for i := 1; ; i++ {
		candidate := filepath.Join(dir, fmt.Sprintf("%s (%d)%s", stem, i, ext))
		if _, err := os.Stat(candidate); os.IsNotExist(err) {
			return candidate
		}
	}
}

func copyRecursive(src, dst string) error {
	info, err := os.Lstat(src)
	if err != nil {
		return err
	}
	// Only the top-level source was resolved against the jail (see Ops.Copy),
	// so a symlink found during recursion is unvalidated. Copying it as a
	// *file* would open it, follow it, and copy the bytes it points at —
	// arbitrary agent-readable content, jail or no jail (PR-05). Recreate the
	// link itself: a link is just a name, and every later read of it goes
	// through Resolve, which re-checks the jail.
	if info.Mode()&os.ModeSymlink != 0 {
		return copySymlink(src, dst)
	}
	if info.IsDir() {
		if err := os.MkdirAll(dst, info.Mode()); err != nil {
			return err
		}
		entries, err := os.ReadDir(src)
		if err != nil {
			return err
		}
		for _, e := range entries {
			if err := copyRecursive(filepath.Join(src, e.Name()), filepath.Join(dst, e.Name())); err != nil {
				return err
			}
		}
		return nil
	}
	return copyFile(src, dst, info.Mode())
}

// copySymlink recreates src's link at dst rather than dereferencing it. An
// existing dst is replaced, matching copyFile's overwrite behaviour.
func copySymlink(src, dst string) error {
	target, err := os.Readlink(src)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	// os.Symlink fails on an existing name, so clear it first. Remove (not
	// RemoveAll) — replacing a non-empty directory is not this call's job.
	if err := os.Remove(dst); err != nil && !os.IsNotExist(err) {
		return err
	}
	return os.Symlink(target, dst)
}

func copyFile(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	// The write side of the same hole: O_CREATE|O_TRUNC on a path that is
	// already a symlink follows it and truncates whatever it points at, which
	// for a link planted in the destination tree is a file outside the jail
	// (PR-05/06). Drop the link and create a real file in its place — the
	// result a copy is supposed to produce anyway.
	//
	// ponytail: Lstat-then-open is still a check/use race against an attacker
	// with concurrent write access to the destination tree; closing that needs
	// descriptor-relative openat traversal (the SecureFS refactor the audit
	// asks for), not a bigger check here.
	if fi, err := os.Lstat(dst); err == nil && fi.Mode()&os.ModeSymlink != 0 {
		if err := os.Remove(dst); err != nil {
			return err
		}
	}
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}

func apiErr(code, msg string) *Error {
	return &Error{Code: code, Message: msg}
}
