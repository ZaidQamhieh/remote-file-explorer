package server

import (
	"os"
	"path/filepath"
	"testing"

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
