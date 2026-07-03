package server

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"

	"testing"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
)

// doRecent invokes recentHandler directly with the given raw query string
// (without the leading '?') and decodes the response.
func doRecent(t *testing.T, ops *fsops.Ops, rawQuery string) (*httptest.ResponseRecorder, []fsops.Entry) {
	t.Helper()
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/fs/recent?"+rawQuery, nil)
	recentHandler(ops)(rr, req)

	var entries []fsops.Entry
	if rr.Code == http.StatusOK {
		if err := json.Unmarshal(rr.Body.Bytes(), &entries); err != nil {
			t.Fatalf("decode body as bare array: %v\nbody: %s", err, rr.Body.String())
		}
	}
	return rr, entries
}

// TestRecentHandler_OrdersNewestFirst uses the shared search fixture (see
// newSearchFixture in search_test.go): 7 files at the fixture root with
// mtimes 2020..2025, plus a nested.jpg (2023) one level deeper.
func TestRecentHandler_OrdersNewestFirst(t *testing.T) {
	ops, _ := newSearchFixture(t)
	rr, entries := doRecent(t, ops, "limit=3")
	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}
	if len(entries) != 3 {
		t.Fatalf("expected 3 entries, got %d: %v", len(entries), names(entries))
	}
	got := names(entries)
	want := []string{"weird.xyz", "archive.zip", "notes.txt"} // 2025, 2024-12, 2024-01
	for i, w := range want {
		if got[i] != w {
			t.Fatalf("position %d: want %q, got %q (full: %v)", i, w, got[i], got)
		}
	}
}

// TestRecentHandler_ExcludesDirectories verifies Subfolder itself never
// appears in results — recent is a files-only feature.
func TestRecentHandler_ExcludesDirectories(t *testing.T) {
	ops, _ := newSearchFixture(t)
	_, entries := doRecent(t, ops, "limit=100")
	if containsName(names(entries), "Subfolder") {
		t.Fatalf("directory should never appear in recent results: %v", names(entries))
	}
	// All 8 files (7 at root + nested.jpg) should be present when the limit
	// comfortably exceeds the fixture's file count.
	if len(entries) != 8 {
		t.Fatalf("expected 8 files, got %d: %v", len(entries), names(entries))
	}
}

// TestRecentHandler_LimitCapsResultCount verifies the top-K heap actually
// keeps only the most recent `limit` entries, not just any `limit` entries.
func TestRecentHandler_LimitCapsResultCount(t *testing.T) {
	ops, _ := newSearchFixture(t)
	_, entries := doRecent(t, ops, "limit=1")
	if len(entries) != 1 {
		t.Fatalf("expected 1 entry, got %d", len(entries))
	}
	if entries[0].Name != "weird.xyz" {
		t.Fatalf("expected the single most recent file (weird.xyz, 2025-05-05), got %q", entries[0].Name)
	}
}

// TestRecentHandler_RootParamScoped verifies the `root` param restricts the
// walk to that subtree (here, Subfolder — containing only nested.jpg).
func TestRecentHandler_RootParamScoped(t *testing.T) {
	ops, dir := newSearchFixture(t)
	_, entries := doRecent(t, ops, "root="+dir+"/Subfolder&limit=100")
	if len(entries) != 1 || entries[0].Name != "nested.jpg" {
		t.Fatalf("expected only nested.jpg scoped to Subfolder, got %v", names(entries))
	}
}

func TestRecentHandler_DefaultLimit(t *testing.T) {
	ops, _ := newSearchFixture(t)
	rr, entries := doRecent(t, ops, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}
	if len(entries) != 8 {
		t.Fatalf("expected all 8 files under the default limit, got %d", len(entries))
	}
}
