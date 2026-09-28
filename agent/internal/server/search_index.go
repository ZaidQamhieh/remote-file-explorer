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
	"unsafe"

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

// Both limits bound each immutable snapshot. During a rebuild the current and
// next snapshots coexist, so the estimate can temporarily double; a byte
// ceiling prevents unusually long names/paths from defeating the entry cap.
const (
	indexMaxEntries        = 2_000_000
	indexMaxEstimatedBytes = 128 << 20
)

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
	Truncated     bool          `json:"truncated"` // hit the entry or estimated-byte limit
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
	var estimatedBytes int64
	truncated := false
	for _, root := range roots {
		openedRoot, err := idx.ops.OpenDir(root)
		if err == nil {
			if collectAllRoot(openedRoot, root, &entries, &estimatedBytes, indexMaxEntries, indexMaxEstimatedBytes) {
				truncated = true
			}
			openedRoot.Close()
		}
		if truncated || len(entries) >= indexMaxEntries {
			truncated = truncated || len(entries) >= indexMaxEntries
			break
		}
	}

	took := time.Since(started)
	idx.mu.Lock()
	idx.entries = entries
	idx.ready = true
	idx.stats = IndexStats{
		Entries:       len(entries),
		Truncated:     truncated,
		BuiltAt:       time.Now(),
		BuildDuration: took,
	}
	idx.mu.Unlock()
	if truncated {
		log.Printf("search index: truncated at %d entries and approximately %d bytes — remaining files are not searchable", len(entries), estimatedBytes)
	}
	return took
}

// collectAll appends every entry under root (skipping virtual pseudo-fs
// dirs, same as walkForMatches) to *entries, obeying both index budgets.
func collectAll(root string, entries *[]indexedEntry) {
	openedRoot, err := os.OpenRoot(root)
	if err != nil {
		return
	}
	defer openedRoot.Close()
	var estimatedBytes int64
	collectAllRoot(openedRoot, root, entries, &estimatedBytes, indexMaxEntries, indexMaxEstimatedBytes)
}

func collectAllRoot(root *os.Root, rootPath string, entries *[]indexedEntry, estimatedBytes *int64, maxEntries int, maxBytes int64) bool {
	truncated := false
	_ = fs.WalkDir(root.FS(), ".", func(relPath string, d fs.DirEntry, err error) error {
		if len(*entries) >= maxEntries {
			truncated = true
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
		entryPath := rootPath
		if relPath != "." {
			entryPath = filepath.Join(rootPath, filepath.FromSlash(relPath))
		}
		if d.IsDir() && relPath != "." && shouldSkipVirtualDir(entryPath) {
			return fs.SkipDir
		}
		if relPath == "." {
			return nil
		}
		info, infoErr := d.Info()
		if infoErr != nil {
			return nil
		}
		// Use the same open root as WalkDir for symlink metadata. The
		// path-based EntryFromInfoNoSniff helper could follow an absolute
		// symlink outside this walk's root while checking its target type.
		// EntryFromRootInfo is also no-sniff, so indexing never reads file
		// contents (PR-47).
		entry := fsops.EntryFromRootInfo(root, rootPath, relPath, info)
		indexed := indexedEntry{
			entry:     entry,
			lowerName: strings.ToLower(entry.Name),
		}
		estimatedEntryBytes := indexedEntryEstimatedBytes(indexed)
		if *estimatedBytes+estimatedEntryBytes > maxBytes {
			truncated = true
			return filepath.SkipAll
		}
		*estimatedBytes += estimatedEntryBytes
		*entries = append(*entries, indexed)
		return nil
	})
	return truncated
}

func indexedEntryEstimatedBytes(entry indexedEntry) int64 {
	bytes := int64(unsafe.Sizeof(entry))
	bytes += estimatedStringBytes(entry.entry.Name)
	bytes += estimatedStringBytes(entry.entry.Path)
	bytes += estimatedStringBytes(entry.entry.MimeType)
	bytes += estimatedStringBytes(entry.entry.Mode)
	bytes += estimatedStringBytes(entry.entry.SymlinkTarget)
	bytes += estimatedStringBytes(entry.lowerName)
	return bytes
}

func estimatedStringBytes(value string) int64 {
	if value == "" {
		return 0
	}
	// Include a small allocation-header allowance for each retained string.
	return int64(len(value) + 16)
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
	// Preserve the rebuild's partial-index status even when this particular
	// query returns fewer than its result limit, so callers can disclose that
	// the remaining tree was omitted by the index's resource budget.
	truncated = idx.stats.Truncated
	// Prepare path-boundary strings once per query. Search may inspect millions
	// of entries, so rebuilding each root's descendant prefix inside the loop
	// needlessly allocates once per entry and root.
	rootScopes := prepareRootScopes(roots)
	for _, ie := range idx.entries {
		if !underAnyRootScopes(ie.entry.Path, rootScopes) {
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
	return results, truncated, true
}

type rootScope struct {
	root             string
	descendantPrefix string
}

func prepareRootScopes(roots []string) []rootScope {
	scopes := make([]rootScope, 0, len(roots))
	separator := string(filepath.Separator)
	for _, root := range roots {
		scopes = append(scopes, rootScope{
			root:             root,
			descendantPrefix: strings.TrimSuffix(root, separator) + separator,
		})
	}
	return scopes
}

// underAnyRootScopes reports whether path is a root itself or inside one of
// the already-prepared roots. It performs no per-root string construction.
func underAnyRootScopes(path string, scopes []rootScope) bool {
	for _, scope := range scopes {
		if path == scope.root || strings.HasPrefix(path, scope.descendantPrefix) {
			return true
		}
	}
	return false
}
