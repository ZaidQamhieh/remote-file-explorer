package server

import (
	"testing"
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
