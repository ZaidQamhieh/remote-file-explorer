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
	"os"
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

// --------- /search GET ---------

func searchHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		q := strings.TrimSpace(r.URL.Query().Get("q"))
		if q == "" {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "q query param required")
			return
		}
		needle := strings.ToLower(q)

		limit := searchDefaultLimit
		if l := r.URL.Query().Get("limit"); l != "" {
			if n, err := strconv.Atoi(l); err == nil && n > 0 {
				limit = n
			}
		}
		if limit > searchMaxLimit {
			limit = searchMaxLimit
		}

		// Determine the set of starting points to walk.
		var roots []string
		if root := r.URL.Query().Get("root"); root != "" {
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
		for _, root := range roots {
			walkForMatches(ctx, root, needle, limit, &results)
			if len(results) >= limit || ctx.Err() != nil {
				break
			}
		}

		writeJSON(w, http.StatusOK, results)
	}
}

// walkForMatches recursively walks root, appending matching entries to
// *results until limit is reached or ctx is done. Permission-denied
// directories are skipped silently; other walk errors are ignored too —
// search is best-effort.
func walkForMatches(ctx context.Context, root, needleLower string, limit int, results *[]fsops.Entry) {
	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
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
		if path != root && strings.Contains(strings.ToLower(d.Name()), needleLower) {
			info, infoErr := d.Info()
			if infoErr == nil {
				*results = append(*results, fsops.EntryFromInfo(info, path))
				if len(*results) >= limit {
					return filepath.SkipAll
				}
			}
		}
		return nil
	})
}
