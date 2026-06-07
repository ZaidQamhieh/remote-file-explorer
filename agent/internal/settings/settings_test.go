package settings

import (
	"path/filepath"
	"testing"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

func newDB(t *testing.T) *store.DB {
	t.Helper()
	db, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { db.Close() })
	return db
}

func TestLoad_SeedsUnsetKeys(t *testing.T) {
	db := newDB(t)
	s, err := Load(db, true, []string{"/home/me"}, "my-pc")
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if !s.IsReadOnly() {
		t.Fatal("expected readOnly seeded true")
	}
	if got := s.Roots(); len(got) != 1 || got[0] != filepath.Clean("/home/me") {
		t.Fatalf("expected roots [/home/me], got %v", got)
	}
	if s.AgentName() != "my-pc" {
		t.Fatalf("expected name my-pc, got %s", s.AgentName())
	}
}

func TestSetters_PersistAndApply(t *testing.T) {
	db := newDB(t)
	s, err := Load(db, false, nil, "pc")
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if err := s.SetReadOnly(true); err != nil {
		t.Fatalf("set ro: %v", err)
	}
	if err := s.SetRoots([]string{"/a", "/a", " /b "}); err != nil {
		t.Fatalf("set roots: %v", err)
	}
	if err := s.SetAgentName("renamed"); err != nil {
		t.Fatalf("set name: %v", err)
	}

	// In-memory reflects immediately.
	if !s.IsReadOnly() {
		t.Fatal("readOnly not applied in memory")
	}
	if got := s.Roots(); len(got) != 2 || got[0] != "/a" || got[1] != "/b" {
		t.Fatalf("roots not normalized/deduped: %v", got)
	}

	// Persisted: a fresh Load sees the new values, not the seeds.
	s2, err := Load(db, false, nil, "pc")
	if err != nil {
		t.Fatalf("reload: %v", err)
	}
	if !s2.IsReadOnly() || s2.AgentName() != "renamed" || len(s2.Roots()) != 2 {
		t.Fatalf("persisted values wrong: ro=%v name=%s roots=%v",
			s2.IsReadOnly(), s2.AgentName(), s2.Roots())
	}
}

func TestLoad_DBValueWinsOverSeed(t *testing.T) {
	db := newDB(t)
	// First load seeds readOnly=true.
	if _, err := Load(db, true, nil, "a"); err != nil {
		t.Fatalf("load1: %v", err)
	}
	// Second load with a different seed must NOT override the persisted value.
	s, err := Load(db, false, nil, "b")
	if err != nil {
		t.Fatalf("load2: %v", err)
	}
	if !s.IsReadOnly() {
		t.Fatal("expected persisted readOnly=true to win over seed=false")
	}
	if s.AgentName() != "a" {
		t.Fatalf("expected persisted name 'a', got %s", s.AgentName())
	}
}
