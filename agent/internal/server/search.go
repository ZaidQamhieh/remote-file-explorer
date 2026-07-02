// Package server — search handler.
//
// Search is implemented as a live recursive directory walk rather than a
// persistent index: this is a personal-use agent over a normal-sized home
// folder, so the cost/complexity of a background-indexed FTS5 store
// (indexing, watchers, staleness handling) isn't worth it. We simply walk
// the tree, matching entry names case-insensitively, and bail out once we
// hit the result limit or a time budget.
package server

import (
	"context"
	"errors"
	"io/fs"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
)

const (
	searchDefaultLimit = 100
	searchMaxLimit     = 500
	searchTimeBudget   = 15 * time.Second
)

// Truncation/partial-result signaling headers. The response body remains a
// bare JSON array of entries for backwards compatibility with the deployed
// app, so these flags travel via headers instead. At most one is set.
const (
	headerSearchTruncated  = "X-Search-Truncated"
	headerSearchTimeBudget = "X-Search-Time-Budget"
)

// categoryExtensions maps each search "types" category to the (lowercase,
// dot-free) file extensions that belong to it. This is the single source of
// truth for the q `types`/`ext` filters below.
var categoryExtensions = map[string][]string{
	"image":    {"jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif", "svg", "avif", "tiff"},
	"video":    {"mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "m4v", "3gp", "mpg", "mpeg"},
	"audio":    {"mp3", "wav", "flac", "ogg", "m4a", "aac", "wma", "opus", "mid"},
	"document": {"pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "odt", "ods", "odp", "rtf", "csv", "epub"},
	"archive":  {"zip", "rar", "7z", "tar", "gz", "bz2", "xz", "zst", "iso", "jar"},
}

// searchCategories is the set of valid `types` values, including the two
// pseudo-categories ("folder" and "other") that aren't extension-based.
var searchCategories = func() map[string]bool {
	set := map[string]bool{"folder": true, "other": true}
	for cat := range categoryExtensions {
		set[cat] = true
	}
	return set
}()

// extToCategory is the reverse index of categoryExtensions, built once.
var extToCategory = func() map[string]string {
	m := make(map[string]string)
	for cat, exts := range categoryExtensions {
		for _, ext := range exts {
			m[ext] = cat
		}
	}
	return m
}()

// CategoryForName returns the search category for a file/folder name:
// "folder" for directories, one of the categoryExtensions keys for files
// with a recognized extension, or "other" otherwise. The extension match is
// case-insensitive and ignores the leading dot.
func CategoryForName(name string, isDir bool) string {
	if isDir {
		return "folder"
	}
	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(name), "."))
	if cat, ok := extToCategory[ext]; ok {
		return cat
	}
	return "other"
}

// extOfName returns the lowercase, dot-free extension of name, or "" if it
// has none.
func extOfName(name string) string {
	return strings.ToLower(strings.TrimPrefix(filepath.Ext(name), "."))
}

// searchFilters holds the parsed/validated optional query filters for v2
// search. A zero-value searchFilters matches everything.
type searchFilters struct {
	glob         string          // lowercase glob pattern, "" if not a glob query
	needle       string          // lowercase substring, "" if glob query
	types        map[string]bool // allowed categories, nil = no filter
	exts         map[string]bool // allowed extensions, nil = no filter
	minSize      int64
	maxSize      int64
	hasMinSize   bool
	hasMaxSize   bool
	hasModAfter  bool
	modAfter     time.Time
	hasModBefore bool
	modBefore    time.Time
}

// isGlobPattern reports whether q should be treated as a glob (path.Match)
// pattern rather than a plain substring.
func isGlobPattern(q string) bool {
	return strings.ContainsAny(q, "*?")
}

// matchName reports whether entryName (as returned by fs.DirEntry.Name)
// matches the q filter (glob or substring, both case-insensitive).
func (f *searchFilters) matchName(entryName string) bool {
	lower := strings.ToLower(entryName)
	if f.glob != "" {
		ok, err := path.Match(f.glob, lower)
		return err == nil && ok
	}
	return strings.Contains(lower, f.needle)
}

// matchEntry reports whether entry satisfies all the non-name filters
// (types, ext, size bounds, modified time bounds). All conditions are
// ANDed together.
func (f *searchFilters) matchEntry(entry *fsops.Entry) bool {
	if f.types != nil {
		if !f.types[CategoryForName(entry.Name, entry.IsDir)] {
			return false
		}
	}
	if f.exts != nil {
		if entry.IsDir || !f.exts[extOfName(entry.Name)] {
			return false
		}
	}
	if f.hasMinSize || f.hasMaxSize {
		if entry.IsDir {
			return false
		}
		if f.hasMinSize && entry.Size < f.minSize {
			return false
		}
		if f.hasMaxSize && entry.Size > f.maxSize {
			return false
		}
	}
	if f.hasModAfter && entry.Modified.Before(f.modAfter) {
		return false
	}
	if f.hasModBefore && entry.Modified.After(f.modBefore) {
		return false
	}
	return true
}

// parseSearchFilters validates and parses the v2 query params. On error it
// returns (nil, code, message) suitable for a 400 response.
func parseSearchFilters(q url.Values) (*searchFilters, string, string) {
	f := &searchFilters{}

	if code, msg := f.applyQueryParam(strings.TrimSpace(q.Get("q"))); code != "" {
		return nil, code, msg
	}
	if code, msg := f.applyTypesParam(strings.TrimSpace(q.Get("types"))); code != "" {
		return nil, code, msg
	}
	f.applyExtParam(strings.TrimSpace(q.Get("ext")))
	if code, msg := f.applySizeBounds(q); code != "" {
		return nil, code, msg
	}
	if code, msg := f.applyModifiedBounds(q); code != "" {
		return nil, code, msg
	}

	return f, "", ""
}

// applyQueryParam sets f.glob or f.needle from the raw `q` value.
func (f *searchFilters) applyQueryParam(rawQ string) (code, message string) {
	if !isGlobPattern(rawQ) {
		f.needle = strings.ToLower(rawQ)
		return "", ""
	}
	f.glob = strings.ToLower(rawQ)
	// Validate the pattern eagerly so bad patterns 400 immediately rather
	// than silently matching nothing on every entry.
	if _, err := path.Match(f.glob, ""); err != nil {
		return "BAD_REQUEST", "invalid glob pattern in q"
	}
	return "", ""
}

// applyTypesParam sets f.types from the comma-separated `types` value.
func (f *searchFilters) applyTypesParam(typesParam string) (code, message string) {
	if typesParam == "" {
		return "", ""
	}
	set := make(map[string]bool)
	for _, raw := range strings.Split(typesParam, ",") {
		t := strings.ToLower(strings.TrimSpace(raw))
		if t == "" {
			continue
		}
		if !searchCategories[t] {
			return "BAD_REQUEST", "invalid types value: " + t
		}
		set[t] = true
	}
	if len(set) > 0 {
		f.types = set
	}
	return "", ""
}

// applyExtParam sets f.exts from the comma-separated `ext` value.
func (f *searchFilters) applyExtParam(extParam string) {
	if extParam == "" {
		return
	}
	set := make(map[string]bool)
	for _, raw := range strings.Split(extParam, ",") {
		e := strings.ToLower(strings.TrimSpace(raw))
		e = strings.TrimPrefix(e, ".")
		if e == "" {
			continue
		}
		set[e] = true
	}
	if len(set) > 0 {
		f.exts = set
	}
}

// applySizeBounds sets f.minSize/f.maxSize from the `minSize`/`maxSize` params.
func (f *searchFilters) applySizeBounds(q url.Values) (code, message string) {
	if minParam := strings.TrimSpace(q.Get("minSize")); minParam != "" {
		n, err := strconv.ParseInt(minParam, 10, 64)
		if err != nil {
			return "BAD_REQUEST", "invalid minSize"
		}
		f.minSize = n
		f.hasMinSize = true
	}
	if maxParam := strings.TrimSpace(q.Get("maxSize")); maxParam != "" {
		n, err := strconv.ParseInt(maxParam, 10, 64)
		if err != nil {
			return "BAD_REQUEST", "invalid maxSize"
		}
		f.maxSize = n
		f.hasMaxSize = true
	}
	return "", ""
}

// applyModifiedBounds sets f.modAfter/f.modBefore from the
// `modifiedAfter`/`modifiedBefore` params.
func (f *searchFilters) applyModifiedBounds(q url.Values) (code, message string) {
	if afterParam := strings.TrimSpace(q.Get("modifiedAfter")); afterParam != "" {
		ts, err := time.Parse(time.RFC3339, afterParam)
		if err != nil {
			return "BAD_REQUEST", "invalid modifiedAfter"
		}
		f.modAfter = ts
		f.hasModAfter = true
	}
	if beforeParam := strings.TrimSpace(q.Get("modifiedBefore")); beforeParam != "" {
		ts, err := time.Parse(time.RFC3339, beforeParam)
		if err != nil {
			return "BAD_REQUEST", "invalid modifiedBefore"
		}
		f.modBefore = ts
		f.hasModBefore = true
	}
	return "", ""
}

// --------- /search GET ---------

func searchHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
		query := r.URL.Query()

		q := strings.TrimSpace(query.Get("q"))
		if q == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "q query param required")
			return
		}

		filters, errCode, errMsg := parseSearchFilters(query)
		if errCode != "" {
			writeError(w, http.StatusBadRequest, errCode, errMsg)
			return
		}

		limit := searchDefaultLimit
		if l := query.Get("limit"); l != "" {
			if n, err := strconv.Atoi(l); err == nil && n > 0 {
				limit = n
			}
		}
		if limit > searchMaxLimit {
			limit = searchMaxLimit
		}

		// Determine the set of starting points to walk.
		var roots []string
		if root := query.Get("root"); root != "" {
			resolved, err := ops.Resolve(root)
			if err != nil {
				handleFsError(w, err)
				return
			}
			roots = []string{resolved}
		} else {
			roots = ops.Roots()
			if len(roots) == 0 {
				// No jail configured — fall back to the user's home directory
				// so an empty root doesn't mean "walk the entire filesystem".
				if home, err := os.UserHomeDir(); err == nil && home != "" {
					roots = []string{home}
				}
			}
		}

		ctx, cancel := context.WithTimeout(r.Context(), searchTimeBudget)
		defer cancel()

		results := make([]fsops.Entry, 0, limit)
		hitLimit := false
		for _, root := range roots {
			walkForMatches(ctx, root, filters, limit, &results, &hitLimit)
			if hitLimit || ctx.Err() != nil {
				break
			}
		}

		// Headers must be set before the body is written.
		if hitLimit {
			w.Header().Set(headerSearchTruncated, "1")
		} else if ctx.Err() != nil {
			w.Header().Set(headerSearchTimeBudget, "1")
		}

		writeJSON(w, http.StatusOK, results)
	}
}

// walkForMatches recursively walks root, appending entries that satisfy
// filters to *results until limit is reached or ctx is done.
// Permission-denied directories are skipped silently; other walk errors are
// ignored too — search is best-effort. *hitLimit is set to true only when
// the walk stops because limit was reached by a matching entry (not merely
// because the time budget expired).
func walkForMatches(ctx context.Context, root string, filters *searchFilters, limit int, results *[]fsops.Entry, hitLimit *bool) {
	_ = filepath.WalkDir(root, func(entryPath string, d fs.DirEntry, err error) error {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if err != nil {
			if errors.Is(err, fs.ErrPermission) {
				if d != nil && d.IsDir() {
					return fs.SkipDir
				}
				return nil
			}
			// Other errors (e.g. transient stat failures): skip this entry.
			if d != nil && d.IsDir() {
				return fs.SkipDir
			}
			return nil
		}

		// Don't match the root itself — only its contents.
		if entryPath != root && filters.matchName(d.Name()) {
			info, infoErr := d.Info()
			if infoErr == nil {
				entry := fsops.EntryFromInfo(info, entryPath)
				if filters.matchEntry(&entry) {
					*results = append(*results, entry)
					if len(*results) >= limit {
						*hitLimit = true
						return filepath.SkipAll
					}
				}
			}
		}
		return nil
	})
}
