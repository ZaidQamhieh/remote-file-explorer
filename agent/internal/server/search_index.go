package server

import (
	"errors"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
)

// indexRebuildInterval balances staleness against cost: a full rebuild is
// one walk of the tree (the same cost a single live search used to pay), so
// this just needs to be often enough that new/moved files show up
// reasonably soon.
//
// ponytail: periodic rebuild, not a live fsnotify watch — upgrade path if
// staleness (new files missing for up to this long) becomes a real problem.
const indexRebuildInterval = 5 * time.Minute

// indexMaxEntries caps memory use against a pathological tree (e.g. an
// accidentally-jailed "/"). At this size the index is still a fast linear
// scan; beyond it we stop collecting rather than grow unbounded.
const indexMaxEntries = 2_000_000

type indexedEntry struct {
	entry     fsops.Entry
	lowerName string
}

// SearchIndex is a warm in-memory copy of every entry under ops.Roots(),
// rebuilt periodically. This is the same fundamental trick behind
// Everything/Spotlight-style instant search: pay the disk-walk cost once in
// the background, then serve queries from memory. See package doc comment
// in search.go.
type SearchIndex struct {
	ops *fsops.Ops

	mu      sync.RWMutex
	entries []indexedEntry
	ready   bool
	stats   IndexStats
}

// IndexStats describes the index's size, age, and cost. Without it a rebuild
// that is quietly truncating or eating the disk is invisible (PR-47).
type IndexStats struct {
	Entries       int           `json:"entries"`
	Truncated     bool          `json:"truncated"` // hit indexMaxEntries; the tail of the tree is unsearchable
	BuiltAt       time.Time     `json:"builtAt"`
	BuildDuration time.Duration `json:"buildDurationMs"`
}

// Stats returns a snapshot of the index's health.
func (idx *SearchIndex) Stats() IndexStats {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	return idx.stats
}

// NewSearchIndex starts building the index in the background and returns
// immediately — server startup isn't blocked on the first walk.
func NewSearchIndex(ops *fsops.Ops) *SearchIndex {
	idx := &SearchIndex{ops: ops}
	go idx.loop()
	return idx
}

// maxIndexDutyCycle bounds the share of wall-clock time the rebuild may
// consume. A walk that takes longer than indexRebuildInterval would otherwise
// have the next one start the moment it ends, pinning a disk permanently —
// the bigger the tree, the worse it gets, which is exactly backwards.
const maxIndexDutyCycle = 10

func (idx *SearchIndex) loop() {
	for {
		took := idx.rebuild()
		// Wait the normal interval, or 10x the last build if that was slower:
		// cost scales with the tree instead of the clock.
		wait := indexRebuildInterval
		if backoff := took * maxIndexDutyCycle; backoff > wait {
			wait = backoff
		}
		time.Sleep(wait)
	}
}

// rebuild walks the roots and swaps in a fresh index, returning how long the
// walk took (the loop uses it to pace itself).
func (idx *SearchIndex) rebuild() time.Duration {
	started := time.Now()
	roots := idx.ops.Roots()
	if len(roots) == 0 {
		if home, err := os.UserHomeDir(); err == nil && home != "" {
			roots = []string{home}
		}
	}

	entries := make([]indexedEntry, 0, 4096)
	for _, root := range roots {
		collectAll(root, &entries)
		if len(entries) >= indexMaxEntries {
			break
		}
	}

	took := time.Since(started)
	idx.mu.Lock()
	idx.entries = entries
	idx.ready = true
	idx.stats = IndexStats{
		Entries:       len(entries),
		Truncated:     len(entries) >= indexMaxEntries,
		BuiltAt:       time.Now(),
		BuildDuration: took,
	}
	idx.mu.Unlock()
	if len(entries) >= indexMaxEntries {
		log.Printf("search index: truncated at %d entries — files beyond the cap are not searchable", indexMaxEntries)
	}
	return took
}

// collectAll appends every entry under root (skipping virtual pseudo-fs
// dirs, same as walkForMatches) to *entries, stopping at indexMaxEntries.
func collectAll(root string, entries *[]indexedEntry) {
	_ = filepath.WalkDir(root, func(entryPath string, d fs.DirEntry, err error) error {
		if len(*entries) >= indexMaxEntries {
			return filepath.SkipAll
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
		if d.IsDir() && entryPath != root && shouldSkipVirtualDir(entryPath) {
			return fs.SkipDir
		}
		if entryPath == root {
			return nil
		}
		info, infoErr := d.Info()
		if infoErr != nil {
			return nil
		}
		// NoSniff: EntryFromInfo opens every extensionless file to sniff its
		// MIME type. Across a whole-tree walk that is an open+read per such
		// file, every rebuild — the dominant cost of indexing (PR-47).
		entry := fsops.EntryFromInfoNoSniff(info, entryPath)
		*entries = append(*entries, indexedEntry{
			entry:     entry,
			lowerName: strings.ToLower(entry.Name),
		})
		return nil
	})
}

// query serves a search from the index. ok is false only while the first
// build is still in flight, telling the caller to fall back to a live walk.
func (idx *SearchIndex) query(
	filters *searchFilters,
	roots []string,
	limit int,
) (results []fsops.Entry, truncated bool, ok bool) {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	if !idx.ready {
		return nil, false, false
	}
	for _, ie := range idx.entries {
		if !underAnyRoot(ie.entry.Path, roots) {
			continue
		}
		if !filters.matchLower(ie.lowerName) {
			continue
		}
		if !filters.matchEntry(&ie.entry) {
			continue
		}
		results = append(results, ie.entry)
		if len(results) >= limit {
			return results, true, true
		}
	}
	return results, false, true
}

// underAnyRoot reports whether path is root itself or inside it, for at
// least one of roots.
func underAnyRoot(path string, roots []string) bool {
	for _, root := range roots {
		if path == root || strings.HasPrefix(path, strings.TrimSuffix(root, string(filepath.Separator))+string(filepath.Separator)) {
			return true
		}
	}
	return false
}
