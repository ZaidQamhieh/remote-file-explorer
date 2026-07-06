// Package server — recent-files handler.
//
// Like search.go, this is a live recursive walk rather than a persistent
// index (personal-use agent, normal-sized home folder — see search.go's doc
// comment for the full reasoning). Unlike search, a recent-files walk can't
// stop early once it has `limit` candidates — the Nth file visited in
// directory-walk order isn't necessarily among the N most recently
// modified — so it keeps a bounded min-heap of the best `limit` candidates
// seen so far instead of collecting everything and sorting at the end.
package server

import (
	"container/heap"
	"context"
	"errors"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
)

const (
	recentDefaultLimit = 100
	recentMaxLimit     = 500
	recentTimeBudget   = 15 * time.Second
)

// recentHeap is a min-heap of fsops.Entry keyed by Modified time — the
// oldest entry is always at the root, so it's the one to evict when a newer
// candidate arrives and the heap is already at limit.
type recentHeap []fsops.Entry

func (h recentHeap) Len() int           { return len(h) }
func (h recentHeap) Less(i, j int) bool { return h[i].Modified.Before(h[j].Modified) }
func (h recentHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *recentHeap) Push(x any)        { *h = append(*h, x.(fsops.Entry)) }
func (h *recentHeap) Pop() any {
	old := *h
	n := len(old)
	item := old[n-1]
	*h = old[:n-1]
	return item
}

// sortedNewestFirst returns h's contents ordered newest-first, without
// mutating h.
func (h recentHeap) sortedNewestFirst() []fsops.Entry {
	out := make([]fsops.Entry, len(h))
	copy(out, h)
	sort.Slice(out, func(i, j int) bool { return out[i].Modified.After(out[j].Modified) })
	return out
}

// recentHandler lists the most recently modified files (not directories)
// under the agent's configured roots — GET /v1/fs/recent?limit=&root=.
func recentHandler(ops *fsops.Ops) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ops := opsFromContext(r.Context(), ops)
		query := r.URL.Query()

		limit := recentDefaultLimit
		if l := query.Get("limit"); l != "" {
			if n, err := strconv.Atoi(l); err == nil && n > 0 {
				limit = n
			}
		}
		if limit > recentMaxLimit {
			limit = recentMaxLimit
		}

		var roots []string
		if root := strings.TrimSpace(query.Get("root")); root != "" {
			resolved, err := ops.Resolve(root)
			if err != nil {
				handleFsError(w, err)
				return
			}
			roots = []string{resolved}
		} else {
			roots = ops.Roots()
			if len(roots) == 0 {
				if home, err := os.UserHomeDir(); err == nil && home != "" {
					roots = []string{home}
				}
			}
		}

		ctx, cancel := context.WithTimeout(r.Context(), recentTimeBudget)
		defer cancel()

		h := &recentHeap{}
		heap.Init(h)
		for _, root := range roots {
			walkForRecent(ctx, root, limit, h)
			if ctx.Err() != nil {
				break
			}
		}

		if ctx.Err() != nil {
			w.Header().Set(headerSearchTimeBudget, "1")
		}

		writeJSON(w, http.StatusOK, h.sortedNewestFirst())
	}
}

// walkForRecent recursively walks root, maintaining h as the top-`limit`
// most recently modified files seen so far (directories are never included
// — recents is a files feature). Permission-denied directories are skipped
// silently; other walk errors are ignored too, matching search.go's
// best-effort behavior.
func walkForRecent(ctx context.Context, root string, limit int, h *recentHeap) {
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
			if d != nil && d.IsDir() {
				return fs.SkipDir
			}
			return nil
		}
		if d.IsDir() {
			if entryPath != root && shouldSkipVirtualDir(entryPath) {
				return fs.SkipDir
			}
			return nil
		}

		info, infoErr := d.Info()
		if infoErr != nil {
			return nil
		}
		entry := fsops.EntryFromInfo(info, entryPath)

		if h.Len() < limit {
			heap.Push(h, entry)
		} else if entry.Modified.After((*h)[0].Modified) {
			(*h)[0] = entry
			heap.Fix(h, 0)
		}
		return nil
	})
}
