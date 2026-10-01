package server

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"unsafe"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
)

func TestSearchIndex_NotReadyBeforeFirstBuild(t *testing.T) {
	idx := &SearchIndex{}
	filters, _, _ := parseSearchFilters(map[string][]string{"q": {"photo"}})
	_, _, ok := idx.query(filters, []string{"/whatever"}, 100)
	if ok {
		t.Fatal("query should report ok=false before rebuild() has run")
	}
}

func TestSearchIndex_RebuildAndQuery(t *testing.T) {
	ops, dir := newSearchFixture(t)
	idx := &SearchIndex{ops: ops}
	idx.rebuild()

	filters, _, _ := parseSearchFilters(map[string][]string{"q": {"photo"}})
	results, truncated, ok := idx.query(filters, []string{dir}, 100)
	if !ok {
		t.Fatal("query should report ok=true after rebuild()")
	}
	if truncated {
		t.Fatal("unexpected truncation for a 2-result query with limit 100")
	}
	if len(results) != 2 {
		t.Fatalf("want 2 photo.* matches, got %d: %+v", len(results), results)
	}

	// Root scoping: querying a root that isn't a prefix of any entry's path
	// must return nothing, even though the index itself isn't empty.
	empty, _, ok := idx.query(filters, []string{"/nonexistent-root"}, 100)
	if !ok || len(empty) != 0 {
		t.Fatalf("query scoped to an unrelated root should return no results, got %+v", empty)
	}
}

func TestSearchIndex_RebuildRespectsLimit(t *testing.T) {
	ops, dir := newSearchFixture(t)
	idx := &SearchIndex{ops: ops}
	idx.rebuild()

	// No "q" filter (matches every name) with a limit smaller than the
	// fixture's entry count should truncate.
	filters, _, _ := parseSearchFilters(map[string][]string{"q": {""}})
	results, truncated, ok := idx.query(filters, []string{dir}, 2)
	if !ok {
		t.Fatal("query should report ok=true after rebuild()")
	}
	if !truncated || len(results) != 2 {
		t.Fatalf("want truncated=true and 2 results, got truncated=%v len=%d", truncated, len(results))
	}
}

func TestSearchIndexQueryReportsPartialIndex(t *testing.T) {
	ops, root := newSearchFixture(t)
	idx := &SearchIndex{ops: ops}
	idx.rebuild()
	idx.mu.Lock()
	idx.stats.Truncated = true
	idx.mu.Unlock()

	filters, _, _ := parseSearchFilters(map[string][]string{"q": {"photo"}})
	results, truncated, ok := idx.query(filters, []string{root}, 100)
	if !ok || len(results) == 0 {
		t.Fatalf("query = (%d results, truncated=%t, ok=%t), want results from the built index", len(results), truncated, ok)
	}
	if !truncated {
		t.Fatal("query omitted the partial-index signal when it was below the result limit")
	}
}

func TestUnderAnyRootScopesPreservesPathBoundaries(t *testing.T) {
	base := t.TempDir()
	root := filepath.Join(base, "allowed")
	scopes := prepareRootScopes([]string{root})

	for _, tc := range []struct {
		name string
		path string
		want bool
	}{
		{name: "root itself", path: root, want: true},
		{name: "child", path: filepath.Join(root, "file.txt"), want: true},
		{name: "nested child", path: filepath.Join(root, "folder", "file.txt"), want: true},
		{name: "shared prefix sibling", path: root + "-other" + string(filepath.Separator) + "file.txt", want: false},
		{name: "outside", path: filepath.Join(base, "other", "file.txt"), want: false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := underAnyRootScopes(tc.path, scopes); got != tc.want {
				t.Fatalf("underAnyRootScopes(%q) = %t, want %t", tc.path, got, tc.want)
			}
		})
	}

	rootWithSeparator := root + string(filepath.Separator)
	trailingSeparatorScopes := prepareRootScopes([]string{rootWithSeparator})
	if child := filepath.Join(root, "file.txt"); !underAnyRootScopes(child, trailingSeparatorScopes) {
		t.Fatalf("root with a trailing separator did not include child %q", child)
	}
}

func TestRootScopeMembershipDoesNotAllocatePerEntry(t *testing.T) {
	root := filepath.Join(t.TempDir(), "allowed")
	path := filepath.Join(root, "nested", "file.txt")
	scopes := prepareRootScopes([]string{root, filepath.Dir(root)})
	allocations := testing.AllocsPerRun(100, func() {
		if !underAnyRootScopes(path, scopes) {
			t.Fatal("expected path to be inside a prepared root")
		}
	})
	if allocations != 0 {
		t.Fatalf("prepared membership check allocated %.2f times per entry, want 0", allocations)
	}
}

// TestSearchIndex_DoesNotSniffDuringWalk is the PR-47 regression: the index
// walk must classify by extension only. EntryFromInfo opens extensionless
// files to sniff them, which across a whole tree is an open+read per file on
// every rebuild.
func TestSearchIndex_DoesNotSniffDuringWalk(t *testing.T) {
	root := t.TempDir()
	// An extensionless file whose contents would sniff as text/plain.
	if err := os.WriteFile(filepath.Join(root, "README"), []byte("hello, this is plain text"), 0o644); err != nil {
		t.Fatal(err)
	}
	var entries []indexedEntry
	collectAll(root, &entries)

	if len(entries) != 1 {
		t.Fatalf("want 1 entry, got %d", len(entries))
	}
	if got := entries[0].entry.MimeType; got != "application/octet-stream" {
		t.Fatalf("index walk sniffed file contents (mime %q); it must classify by extension alone", got)
	}
}

func TestSearchIndex_DoesNotFollowSymlinkOutsideOpenedRoot(t *testing.T) {
	root := t.TempDir()
	outside := t.TempDir()
	if err := os.WriteFile(filepath.Join(outside, "secret-marker.txt"), []byte("private"), 0o600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(root, "outside-link")
	if err := os.Symlink(outside, link); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}

	idx := &SearchIndex{ops: fsops.New([]string{root}, false)}
	idx.rebuild()
	filters, _, _ := parseSearchFilters(map[string][]string{"q": {""}})
	results, _, ok := idx.query(filters, []string{root}, 100)
	if !ok {
		t.Fatal("search index did not become ready")
	}
	foundLink := false
	for _, result := range results {
		if result.Name == "secret-marker.txt" {
			t.Fatal("search indexed an entry from outside the opened root")
		}
		if result.Name == "outside-link" {
			foundLink = true
			if result.IsDir {
				t.Fatal("search followed an outside symlink while reading its metadata")
			}
		}
	}
	if !foundLink {
		t.Fatal("expected the in-root symlink entry to remain visible")
	}
}

func TestCollectAllRootHonorsEstimatedMemoryBudget(t *testing.T) {
	root := t.TempDir()
	for _, name := range []string{"a.txt", "b.txt"} {
		if err := os.WriteFile(filepath.Join(root, name), []byte("x"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	openedRoot, err := os.OpenRoot(root)
	if err != nil {
		t.Fatal(err)
	}
	defer openedRoot.Close()

	info, err := os.Stat(filepath.Join(root, "a.txt"))
	if err != nil {
		t.Fatal(err)
	}
	entry := fsops.EntryFromRootInfo(openedRoot, root, "a.txt", info)
	limit := indexedEntryEstimatedBytes(indexedEntry{
		entry:     entry,
		lowerName: strings.ToLower(entry.Name),
	})
	var entries []indexedEntry
	var estimated int64
	truncated := collectAllRoot(openedRoot, root, &entries, &estimated, 100, limit)
	if !truncated || len(entries) != 1 || estimated != limit {
		t.Fatalf("memory-limited walk = (truncated=%t entries=%d estimated=%d limit=%d), want one entry at the limit", truncated, len(entries), estimated, limit)
	}
}

// TestSearchIndex_StatsReported: an index that is silently truncating or
// thrashing must be observable.
func TestSearchIndex_StatsReported(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "a.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	idx := &SearchIndex{ops: fsops.New([]string{root}, false)}
	idx.rebuild()

	st := idx.Stats()
	if st.Entries != 1 {
		t.Fatalf("want 1 indexed entry, got %d", st.Entries)
	}
	if st.Truncated {
		t.Fatal("a one-file tree must not report truncated")
	}
	if st.BuiltAt.IsZero() {
		t.Fatal("BuiltAt not stamped — index age is unobservable")
	}
}

func TestCompactIndexedEntrySharesNameAndInternsRepeats(t *testing.T) {
	intern := newStringInterner()
	mk := func(dir string) fsops.Entry {
		return fsops.Entry{
			Name:     strings.Clone("report.pdf"),
			Path:     strings.Clone(dir + "/report.pdf"),
			Mode:     strings.Clone("-rw-r--r--"),
			MimeType: strings.Clone("application/pdf"),
		}
	}
	a, b := mk("/data/a"), mk("/data/b")
	compactIndexedEntry(&a, intern)
	compactIndexedEntry(&b, intern)

	if a.Name != "report.pdf" || a.Path != "/data/a/report.pdf" {
		t.Fatalf("compaction changed values: %+v", a)
	}
	// Name is a view into Path, not a second allocation.
	if unsafe.StringData(a.Name) != unsafe.StringData(a.Path[len(a.Path)-len(a.Name):]) {
		t.Fatal("Name does not share Path's memory")
	}
	if unsafe.StringData(a.Mode) != unsafe.StringData(b.Mode) || unsafe.StringData(a.MimeType) != unsafe.StringData(b.MimeType) {
		t.Fatal("repeated Mode/MimeType were not interned")
	}
	// Negative control: a name that is not the path's tail is left alone.
	odd := fsops.Entry{Name: "x", Path: "/data/y"}
	compactIndexedEntry(&odd, intern)
	if odd.Name != "x" {
		t.Fatalf("name rewritten without a matching suffix: %q", odd.Name)
	}
}
