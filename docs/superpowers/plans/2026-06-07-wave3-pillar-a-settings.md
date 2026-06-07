# Wave 3 Pillar A — Remote Settings & Device Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the phone reconfigure the host agent remotely — toggle read-only, edit the folder jail, revoke paired devices, and rename the agent — with changes taking effect immediately (no restart).

**Architecture:** A new mutex-guarded `settings.Store` persists `readOnly`, `roots`, and `agentName` in the existing `config` table and is consulted by `fsops` per-operation (via a `SettingsView` interface). CLI flags become first-run seeds only. New authenticated endpoints expose settings + device management; a Flutter Settings screen drives them through the existing pinned `AgentClient`.

**Tech Stack:** Go (chi, modernc.org/sqlite, stdlib testing/httptest), Flutter/Dart (Riverpod 2.6.1, dio).

**Spec:** `docs/superpowers/specs/2026-06-07-wave3-settings-updater-polish-design.md` (Pillar A).

**Environment:** `export PATH="$HOME/.local/go/bin:$PATH"` for Go; `export PATH="$HOME/flutter/bin:$PATH"` for Flutter. Run Go commands from `agent/`, Flutter from `app/`.

---

## File Structure

**Agent (Go)**
- Create: `agent/internal/settings/settings.go` — live-mutable settings store
- Create: `agent/internal/settings/settings_test.go` — unit tests
- Modify: `agent/internal/fsops/fsops.go` — read `readOnly`/`roots` through a `SettingsView`
- Modify: `agent/internal/store/store.go` — `ListDevices`, `RevokeDevice`
- Modify: `agent/internal/store/store_test.go` (create if absent) — device list/revoke tests
- Create: `agent/internal/server/settings_handlers.go` — `/settings`, `/devices` handlers
- Create: `agent/internal/server/settings_handlers_test.go` — handler tests
- Modify: `agent/internal/server/server.go` — `Config` gains `*settings.Store`; build ops via `fsops.NewWithSettings`; register routes
- Modify: `agent/cmd/agent/main.go` — build the settings store, seed from flags, pass to server
- Modify: `protocol/openapi.yaml` — document new endpoints

**App (Flutter)**
- Create: `app/lib/core/models/agent_settings.dart`
- Create: `app/lib/core/models/device.dart`
- Modify: `app/lib/core/models/agent_settings.dart` tests in `app/test/models_test.dart`
- Modify: `app/lib/core/api/agent_client.dart` — `getSettings`, `updateSettings`, `listDevices`, `revokeDevice`
- Create: `app/lib/features/settings/settings_screen.dart`
- Modify: `app/lib/features/hosts/host_list_screen.dart` — entry point (overflow menu → Settings)

---

## Task 1: `settings.Store` — load + seed

**Files:**
- Create: `agent/internal/settings/settings.go`
- Test: `agent/internal/settings/settings_test.go`

- [ ] **Step 1: Write the failing test**

```go
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go test ./internal/settings/ -run TestLoad -v`
Expected: FAIL — `undefined: Load` (package doesn't compile).

- [ ] **Step 3: Write minimal implementation**

```go
// Package settings holds the agent's live-mutable configuration (read-only
// mode, the folder jail, and the display name), persisted in the config table
// so changes made from the phone take effect immediately without a restart.
package settings

import (
	"path/filepath"
	"strings"
	"sync"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

const (
	keyReadOnly  = "readOnly"
	keyRoots     = "roots"
	keyAgentName = "agentName"
)

// Store is a concurrency-safe view over the agent's settings.
type Store struct {
	db        *store.DB
	mu        sync.RWMutex
	readOnly  bool
	roots     []string
	agentName string
}

// Load builds a Store. Any config key that is unset is seeded from the
// provided default (typically a CLI flag) and written back; once a key exists
// in the DB, the persisted value wins on every subsequent load.
func Load(db *store.DB, seedReadOnly bool, seedRoots []string, seedName string) (*Store, error) {
	s := &Store{db: db}

	ro, err := db.GetConfig(keyReadOnly)
	if err != nil {
		return nil, err
	}
	if ro == "" {
		s.readOnly = seedReadOnly
		if err := db.SetConfig(keyReadOnly, boolToStr(seedReadOnly)); err != nil {
			return nil, err
		}
	} else {
		s.readOnly = ro == "true"
	}

	rts, err := db.GetConfig(keyRoots)
	if err != nil {
		return nil, err
	}
	if rts == "" {
		s.roots = normalizeRoots(seedRoots)
		if err := db.SetConfig(keyRoots, joinRoots(s.roots)); err != nil {
			return nil, err
		}
	} else {
		s.roots = splitRoots(rts)
	}

	nm, err := db.GetConfig(keyAgentName)
	if err != nil {
		return nil, err
	}
	if nm == "" {
		s.agentName = seedName
		if err := db.SetConfig(keyAgentName, seedName); err != nil {
			return nil, err
		}
	} else {
		s.agentName = nm
	}

	return s, nil
}

// IsReadOnly reports whether writes are currently rejected.
func (s *Store) IsReadOnly() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.readOnly
}

// Roots returns a copy of the current jail roots (empty = allow all).
func (s *Store) Roots() []string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]string, len(s.roots))
	copy(out, s.roots)
	return out
}

// AgentName returns the current display name.
func (s *Store) AgentName() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.agentName
}

func boolToStr(b bool) string {
	if b {
		return "true"
	}
	return "false"
}

// roots are stored newline-joined (paths may contain commas but not newlines).
func joinRoots(roots []string) string { return strings.Join(roots, "\n") }

func splitRoots(v string) []string {
	return normalizeRoots(strings.Split(v, "\n"))
}

func normalizeRoots(in []string) []string {
	seen := make(map[string]struct{}, len(in))
	out := make([]string, 0, len(in))
	for _, r := range in {
		r = strings.TrimSpace(r)
		if r == "" {
			continue
		}
		c := filepath.Clean(r)
		if _, dup := seen[c]; dup {
			continue
		}
		seen[c] = struct{}{}
		out = append(out, c)
	}
	return out
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go test ./internal/settings/ -run TestLoad -v`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add agent/internal/settings/settings.go agent/internal/settings/settings_test.go
git commit -m "feat(agent): live-mutable settings store with first-run seeding"
```

---

## Task 2: `settings.Store` — setters persist + update in memory

**Files:**
- Modify: `agent/internal/settings/settings.go`
- Test: `agent/internal/settings/settings_test.go`

- [ ] **Step 1: Write the failing test**

```go
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go test ./internal/settings/ -run TestSetters -v`
Expected: FAIL — `s.SetReadOnly undefined`.

- [ ] **Step 3: Write minimal implementation** (append to `settings.go`)

```go
// SetReadOnly persists and applies the read-only flag.
func (s *Store) SetReadOnly(v bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.db.SetConfig(keyReadOnly, boolToStr(v)); err != nil {
		return err
	}
	s.readOnly = v
	return nil
}

// SetRoots normalizes, persists, and applies the jail roots.
func (s *Store) SetRoots(roots []string) error {
	norm := normalizeRoots(roots)
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.db.SetConfig(keyRoots, joinRoots(norm)); err != nil {
		return err
	}
	s.roots = norm
	return nil
}

// SetAgentName persists and applies the display name.
func (s *Store) SetAgentName(name string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.db.SetConfig(keyAgentName, name); err != nil {
		return err
	}
	s.agentName = name
	return nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go test ./internal/settings/ -v`
Expected: PASS (all settings tests).

- [ ] **Step 5: Commit**

```bash
git add agent/internal/settings/settings.go agent/internal/settings/settings_test.go
git commit -m "feat(agent): settings setters persist and apply live"
```

---

## Task 3: `fsops` reads through a `SettingsView`

**Files:**
- Modify: `agent/internal/fsops/fsops.go:32-57` (struct + `New` + `Roots`) and the write-guard sites (`o.readOnly`) and `Resolve` (`o.allowedRoots`)
- Test: `agent/internal/fsops/fsops_test.go`

- [ ] **Step 1: Write the failing test**

```go
// Append to fsops_test.go

// fakeSettings is a mutable SettingsView for testing live config.
type fakeSettings struct {
	ro    bool
	roots []string
}

func (f *fakeSettings) IsReadOnly() bool { return f.ro }
func (f *fakeSettings) Roots() []string  { return f.roots }

func TestOps_LiveReadOnlyToggle(t *testing.T) {
	root := t.TempDir()
	fs := &fakeSettings{ro: false, roots: []string{root}}
	ops := NewWithSettings(fs)

	if _, err := ops.CreateFolder(filepath.Join(root, "ok")); err != nil {
		t.Fatalf("write should succeed when not read-only: %v", err)
	}
	// Flip read-only live — no reconstruction of ops.
	fs.ro = true
	if _, err := ops.CreateFolder(filepath.Join(root, "blocked")); err == nil {
		t.Fatal("expected write to be rejected after read-only toggled on")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go test ./internal/fsops/ -run TestOps_LiveReadOnlyToggle -v`
Expected: FAIL — `undefined: NewWithSettings`.

- [ ] **Step 3: Write minimal implementation**

In `agent/internal/fsops/fsops.go`, replace the struct + constructor + `Roots` (currently lines ~32-57):

```go
// SettingsView supplies the live read-only flag and jail roots. fsops reads
// through it on every operation so changes apply without reconstructing Ops.
type SettingsView interface {
	IsReadOnly() bool
	Roots() []string
}

// staticSettings is an immutable SettingsView for callers (and tests) that
// pass fixed values via New.
type staticSettings struct {
	readOnly bool
	roots    []string
}

func (s staticSettings) IsReadOnly() bool { return s.readOnly }
func (s staticSettings) Roots() []string  { return s.roots }

// Ops performs jailed filesystem operations.
type Ops struct {
	settings SettingsView
}

// New builds an Ops with fixed roots and read-only flag (back-compat:
// existing callers and tests keep working).
func New(allowedRoots []string, readOnly bool) *Ops {
	roots := make([]string, 0, len(allowedRoots))
	for _, r := range allowedRoots {
		clean := filepath.Clean(r)
		if clean != "" && clean != "." {
			roots = append(roots, clean)
		}
	}
	return &Ops{settings: staticSettings{readOnly: readOnly, roots: roots}}
}

// NewWithSettings builds an Ops backed by a live SettingsView.
func NewWithSettings(v SettingsView) *Ops {
	return &Ops{settings: v}
}

// Roots returns the configured allowed roots (a copy). An empty slice
// means "allow all".
func (o *Ops) Roots() []string {
	src := o.settings.Roots()
	roots := make([]string, len(src))
	copy(roots, src)
	return roots
}
```

Then update every internal read:
- In `Resolve` (and anywhere else iterating roots), replace `o.allowedRoots` with `o.settings.Roots()` (assign to a local `roots := o.settings.Roots()` at the top of the function and iterate that).
- In each write method (`CreateFolder`, `CreateFile`, `Rename`, `Copy`, `Move`, `Delete`), replace `if o.readOnly {` with `if o.settings.IsReadOnly() {`.

Run this to find every site to change:
`cd agent && grep -n "o.readOnly\|o.allowedRoots" internal/fsops/fsops.go`
Replace each occurrence as above.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go test ./internal/fsops/ -v`
Expected: PASS — existing jail/traversal tests AND the new `TestOps_LiveReadOnlyToggle` all pass.

- [ ] **Step 5: Commit**

```bash
git add agent/internal/fsops/fsops.go agent/internal/fsops/fsops_test.go
git commit -m "refactor(agent): fsops reads read-only and roots through a live SettingsView"
```

---

## Task 4: Store — `ListDevices` and `RevokeDevice`

**Files:**
- Modify: `agent/internal/store/store.go` (after `scanDevice`, ~line 129)
- Test: Create `agent/internal/store/store_test.go`

- [ ] **Step 1: Write the failing test**

```go
package store

import (
	"testing"
)

func TestListAndRevokeDevices(t *testing.T) {
	db, err := Open(t.TempDir())
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer db.Close()

	if err := db.CreateDevice("id-1", "phone-a", "tok-a"); err != nil {
		t.Fatalf("create a: %v", err)
	}
	if err := db.CreateDevice("id-2", "phone-b", "tok-b"); err != nil {
		t.Fatalf("create b: %v", err)
	}

	list, err := db.ListDevices()
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(list) != 2 {
		t.Fatalf("expected 2 devices, got %d", len(list))
	}

	if err := db.RevokeDevice("id-1"); err != nil {
		t.Fatalf("revoke: %v", err)
	}
	// A revoked device's token no longer resolves to a usable device.
	d, err := db.DeviceByToken("tok-a")
	if err != nil {
		t.Fatalf("by token: %v", err)
	}
	if d == nil || !d.Revoked {
		t.Fatalf("expected device present and revoked, got %+v", d)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go test ./internal/store/ -run TestListAndRevokeDevices -v`
Expected: FAIL — `db.ListDevices undefined`.

- [ ] **Step 3: Write minimal implementation** (add to `store.go` after `scanDevice`)

```go
// rowScanner is satisfied by both *sql.Row and *sql.Rows.
type rowScanner interface {
	Scan(dest ...any) error
}

func scanDeviceFrom(sc rowScanner) (*Device, error) {
	var d Device
	var created, lastSeen int64
	var revoked int
	if err := sc.Scan(&d.ID, &d.Label, &d.TokenHash, &created, &lastSeen, &revoked); err != nil {
		return nil, err
	}
	d.Created = time.Unix(created, 0)
	d.LastSeen = time.Unix(lastSeen, 0)
	d.Revoked = revoked != 0
	return &d, nil
}

// ListDevices returns all paired devices (including revoked), oldest first.
func (s *DB) ListDevices() ([]Device, error) {
	rows, err := s.db.Query(
		`SELECT id,label,token_hash,created,last_seen,revoked FROM devices ORDER BY created`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Device
	for rows.Next() {
		d, err := scanDeviceFrom(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *d)
	}
	return out, rows.Err()
}

// RevokeDevice marks a device revoked; its token is rejected by authMiddleware.
func (s *DB) RevokeDevice(id string) error {
	_, err := s.db.Exec(`UPDATE devices SET revoked=1 WHERE id=?`, id)
	return err
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go test ./internal/store/ -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add agent/internal/store/store.go agent/internal/store/store_test.go
git commit -m "feat(agent): store ListDevices and RevokeDevice"
```

---

## Task 5: Server — settings + devices handlers

**Files:**
- Create: `agent/internal/server/settings_handlers.go`
- Modify: `agent/internal/server/server.go` (Config + New + routes)
- Test: Create `agent/internal/server/settings_handlers_test.go`

- [ ] **Step 1: Write the failing test**

```go
package server

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/settings"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

func newTestDeps(t *testing.T) (*store.DB, *settings.Store) {
	t.Helper()
	db, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatalf("store: %v", err)
	}
	t.Cleanup(func() { db.Close() })
	st, err := settings.Load(db, false, nil, "test-pc")
	if err != nil {
		t.Fatalf("settings: %v", err)
	}
	return db, st
}

func TestSettingsHandler_GetAndPatch(t *testing.T) {
	_, st := newTestDeps(t)

	// GET reflects defaults.
	rr := httptest.NewRecorder()
	getSettingsHandler(st)(rr, httptest.NewRequest(http.MethodGet, "/v1/settings", nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("GET code = %d", rr.Code)
	}
	var got map[string]any
	_ = json.Unmarshal(rr.Body.Bytes(), &got)
	if got["readOnly"] != false || got["agentName"] != "test-pc" {
		t.Fatalf("unexpected GET body: %v", got)
	}

	// PATCH toggles read-only and renames.
	body := `{"readOnly":true,"agentName":"new-name"}`
	rr2 := httptest.NewRecorder()
	patchSettingsHandler(st)(rr2, httptest.NewRequest(http.MethodPatch, "/v1/settings", strings.NewReader(body)))
	if rr2.Code != http.StatusOK {
		t.Fatalf("PATCH code = %d", rr2.Code)
	}
	if !st.IsReadOnly() || st.AgentName() != "new-name" {
		t.Fatalf("settings not applied: ro=%v name=%s", st.IsReadOnly(), st.AgentName())
	}
}

func TestDevicesHandler_ListAndRevoke(t *testing.T) {
	db, _ := newTestDeps(t)
	_ = db.CreateDevice("id-keep", "keeper", "tok-keep")
	_ = db.CreateDevice("id-gone", "gone", "tok-gone")

	// Current device = the keeper (simulate auth context).
	cur, _ := db.DeviceByToken("tok-keep")

	// LIST marks current.
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/devices", nil)
	req = req.WithContext(withDevice(req.Context(), cur))
	listDevicesHandler(db)(rr, req)
	var list []map[string]any
	_ = json.Unmarshal(rr.Body.Bytes(), &list)
	if len(list) != 2 {
		t.Fatalf("expected 2 devices, got %d", len(list))
	}

	// Revoking self is rejected (409).
	rrSelf := httptest.NewRecorder()
	reqSelf := httptest.NewRequest(http.MethodDelete, "/v1/devices/id-keep", nil)
	reqSelf = reqSelf.WithContext(withDevice(reqSelf.Context(), cur))
	revokeDeviceHandler(db)(rrSelf, reqSelf, "id-keep")
	if rrSelf.Code != http.StatusConflict {
		t.Fatalf("expected 409 on self-revoke, got %d", rrSelf.Code)
	}

	// Revoking another succeeds.
	rrOther := httptest.NewRecorder()
	reqOther := httptest.NewRequest(http.MethodDelete, "/v1/devices/id-gone", nil)
	reqOther = reqOther.WithContext(withDevice(reqOther.Context(), cur))
	revokeDeviceHandler(db)(rrOther, reqOther, "id-gone")
	if rrOther.Code != http.StatusNoContent {
		t.Fatalf("expected 204 revoking other, got %d", rrOther.Code)
	}
	gone, _ := db.DeviceByToken("tok-gone")
	if gone == nil || !gone.Revoked {
		t.Fatal("expected id-gone to be revoked")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go test ./internal/server/ -run "TestSettingsHandler|TestDevicesHandler" -v`
Expected: FAIL — `getSettingsHandler undefined`, `withDevice undefined`.

- [ ] **Step 3: Write minimal implementation** — create `settings_handlers.go`

```go
// Package server — settings and device-management route handlers.
package server

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/settings"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

// withDevice injects a device into a context (test seam mirroring authMiddleware).
func withDevice(ctx context.Context, d *store.Device) context.Context {
	return context.WithValue(ctx, deviceCtxKey, d)
}

func deviceFromContext(r *http.Request) *store.Device {
	d, _ := r.Context().Value(deviceCtxKey).(*store.Device)
	return d
}

type settingsBody struct {
	ReadOnly  *bool     `json:"readOnly,omitempty"`
	Roots     *[]string `json:"roots,omitempty"`
	AgentName *string   `json:"agentName,omitempty"`
}

func getSettingsHandler(st *settings.Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"readOnly":  st.IsReadOnly(),
			"roots":     st.Roots(),
			"agentName": st.AgentName(),
		})
	}
}

func patchSettingsHandler(st *settings.Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var b settingsBody
		if err := json.NewDecoder(r.Body).Decode(&b); err != nil {
			writeError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid JSON body")
			return
		}
		if b.ReadOnly != nil {
			if err := st.SetReadOnly(*b.ReadOnly); err != nil {
				writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
		}
		if b.Roots != nil {
			if err := st.SetRoots(*b.Roots); err != nil {
				writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
		}
		if b.AgentName != nil {
			if err := st.SetAgentName(*b.AgentName); err != nil {
				writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"readOnly":  st.IsReadOnly(),
			"roots":     st.Roots(),
			"agentName": st.AgentName(),
		})
	}
}

func listDevicesHandler(db *store.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		devices, err := db.ListDevices()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		cur := deviceFromContext(r)
		out := make([]map[string]any, 0, len(devices))
		for _, d := range devices {
			out = append(out, map[string]any{
				"id":       d.ID,
				"label":    d.Label,
				"created":  d.Created.Unix(),
				"lastSeen": d.LastSeen.Unix(),
				"revoked":  d.Revoked,
				"current":  cur != nil && cur.ID == d.ID,
			})
		}
		writeJSON(w, http.StatusOK, out)
	}
}

// revokeDeviceHandler revokes device `id`. The third arg is the URL path param
// (the route wrapper passes chi.URLParam so this stays unit-testable).
func revokeDeviceHandler(db *store.DB) func(http.ResponseWriter, *http.Request, string) {
	return func(w http.ResponseWriter, r *http.Request, id string) {
		cur := deviceFromContext(r)
		if cur != nil && cur.ID == id {
			writeError(w, http.StatusConflict, "CONFLICT", "cannot revoke the device you are using")
			return
		}
		if err := db.RevokeDevice(id); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go test ./internal/server/ -run "TestSettingsHandler|TestDevicesHandler" -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add agent/internal/server/settings_handlers.go agent/internal/server/settings_handlers_test.go
git commit -m "feat(agent): settings and device-management handlers"
```

---

## Task 6: Wire settings into `server.New` and `main.go`

**Files:**
- Modify: `agent/internal/server/server.go:20-85`
- Modify: `agent/cmd/agent/main.go`

- [ ] **Step 1: Update `server.Config` and `New`**

In `server.go`, change `Config` to carry the settings store and drop the now-derived fields:

```go
// Config holds the runtime settings the server needs.
type Config struct {
	Name             string
	Version          string
	CertFingerprint  string
	Address          string
	TailscaleAddress string
	ThumbCacheDir    string
	Settings         *settings.Store
}
```

Add the import `"github.com/zqamhieh/remote-file-explorer/agent/internal/settings"`. In `New`, build ops from the live settings and register the new routes:

```go
func New(cfg Config, db *store.DB, pm *pairing.Manager, tm *transfer.Manager) (http.Handler, error) {
	ops := fsops.NewWithSettings(cfg.Settings)

	thumbRenderer, err := thumbs.New(cfg.ThumbCacheDir)
	if err != nil {
		return nil, err
	}

	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recoverer)

	r.Route("/v1", func(r chi.Router) {
		r.Get("/health", healthHandler(cfg))
		r.Post("/pair", pairHandler(cfg, db, pm))

		r.Group(func(r chi.Router) {
			r.Use(authMiddleware(db))

			// Settings & devices
			r.Get("/settings", getSettingsHandler(cfg.Settings))
			r.Patch("/settings", patchSettingsHandler(cfg.Settings))
			r.Get("/devices", listDevicesHandler(db))
			r.Delete("/devices/{id}", func(w http.ResponseWriter, req *http.Request) {
				revokeDeviceHandler(db)(w, req, chi.URLParam(req, "id"))
			})

			r.Get("/system/drives", drivesHandler())
			r.Get("/search", searchHandler(ops))
			r.Get("/thumb", thumbHandler(ops, thumbRenderer))
			r.Get("/fs", listDirHandler(ops))
			r.Delete("/fs", deleteHandler(ops))
			r.Post("/fs/folder", createFolderHandler(ops))
			r.Post("/fs/file", createFileHandler(ops))
			r.Patch("/fs/rename", renameHandler(ops))
			r.Post("/fs/copy", copyHandler(ops))
			r.Post("/fs/move", moveHandler(ops))
			r.Get("/fs/meta", metaHandler(ops))
			r.Get("/content", downloadHandler(ops))
			r.Post("/transfers", openTransferHandler(tm, ops))
			r.Get("/transfers/{id}", transferStatusHandler(tm))
			r.Put("/transfers/{id}/chunks/{n}", uploadChunkHandler(tm))
			r.Post("/transfers/{id}/complete", completeTransferHandler(tm, ops))
		})
	})

	return r, nil
}
```

Update `healthHandler` to read the live name. Replace its `"name": cfg.Name` with `"name": cfg.Settings.AgentName()` (so a rename is reflected) — change the line in `healthHandler` (server.go ~line 112) accordingly. Keep `ReadOnly` out of health or source it from `cfg.Settings.IsReadOnly()` if present.

- [ ] **Step 2: Update `main.go`** to build the settings store and pass it

In `agent/cmd/agent/main.go`, after `db` is opened and before `pairing.New`, build the settings store, and replace the `allowedRoots` parsing + `server.Config` literal:

```go
	// Parse seed roots from the flag (first-run only; DB wins thereafter).
	var seedRoots []string
	if *roots != "" {
		for _, r := range strings.Split(*roots, ",") {
			if r = strings.TrimSpace(r); r != "" {
				seedRoots = append(seedRoots, r)
			}
		}
	}

	st, err := settings.Load(db, *readOnly, seedRoots, *name)
	if err != nil {
		log.Fatalf("settings: %v", err)
	}

	handler, err := server.New(server.Config{
		Name:             st.AgentName(),
		Version:          version,
		CertFingerprint:  fingerprint,
		Address:          lanAddr,
		TailscaleAddress: tsAddr,
		ThumbCacheDir:    thumbCacheDir,
		Settings:         st,
	}, db, pm, tm)
	if err != nil {
		log.Fatalf("server: %v", err)
	}
```

Add the import `"github.com/zqamhieh/remote-file-explorer/agent/internal/settings"`. Remove the old standalone `allowedRoots` block and the removed `ReadOnly`/`AllowedRoots` Config fields.

- [ ] **Step 3: Build the whole agent**

Run: `cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go build ./... && go test ./...`
Expected: build clean; all tests PASS.

- [ ] **Step 4: End-to-end smoke test (live toggle, no restart)**

```bash
cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go build -o /tmp/rfe-agent ./cmd/agent
/tmp/rfe-agent -addr 127.0.0.1:8799 -data /tmp/rfe-a-test -name smoke &
sleep 1
# Grab the pairing code from the agent log line "PAIRING CODE:  XXXX"
```
Pair via curl (reuse the Wave 2 flow), capture `$TOKEN`, then:
```bash
curl -sk https://127.0.0.1:8799/v1/settings -H "Authorization: Bearer $TOKEN"
# expect {"readOnly":false,...}
curl -sk -X PATCH https://127.0.0.1:8799/v1/settings -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"readOnly":true}'
curl -sk -X POST https://127.0.0.1:8799/v1/fs/folder -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"path":"/tmp/rfe-a-test/should-fail"}' -w '\n%{http_code}\n'
# expect 403 — read-only now in effect WITHOUT restarting the agent
kill %1
```
Expected: GET shows defaults, PATCH succeeds, the folder create returns `403`.

- [ ] **Step 5: Commit**

```bash
git add agent/internal/server/server.go agent/cmd/agent/main.go
git commit -m "feat(agent): wire live settings store into server and main; live read-only verified"
```

---

## Task 7: OpenAPI — document the new endpoints

**Files:**
- Modify: `protocol/openapi.yaml`

- [ ] **Step 1: Add path entries**

Under `paths:`, add (matching the existing style in the file):

```yaml
  /settings:
    get:
      summary: Get agent settings
      security: [{ deviceToken: [] }]
      responses:
        '200':
          description: Current settings
          content:
            application/json:
              schema: { $ref: '#/components/schemas/AgentSettings' }
    patch:
      summary: Update agent settings (partial)
      security: [{ deviceToken: [] }]
      requestBody:
        content:
          application/json:
            schema: { $ref: '#/components/schemas/AgentSettings' }
      responses:
        '200':
          description: Updated settings
          content:
            application/json:
              schema: { $ref: '#/components/schemas/AgentSettings' }
  /devices:
    get:
      summary: List paired devices
      security: [{ deviceToken: [] }]
      responses:
        '200':
          description: Devices
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/Device' }
  /devices/{id}:
    delete:
      summary: Revoke a paired device
      security: [{ deviceToken: [] }]
      parameters:
        - { name: id, in: path, required: true, schema: { type: string } }
      responses:
        '204': { description: Revoked }
        '409': { description: Cannot revoke the calling device }
```

Under `components.schemas`, add:

```yaml
    AgentSettings:
      type: object
      properties:
        readOnly: { type: boolean }
        roots:
          type: array
          items: { type: string }
        agentName: { type: string }
    Device:
      type: object
      properties:
        id: { type: string }
        label: { type: string }
        created: { type: integer, format: int64 }
        lastSeen: { type: integer, format: int64 }
        revoked: { type: boolean }
        current: { type: boolean }
```

- [ ] **Step 2: Validate YAML parses**

Run: `cd ~/Storage/Projects/remote-file-explorer && python3 -c "import yaml; yaml.safe_load(open('protocol/openapi.yaml'))" && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add protocol/openapi.yaml
git commit -m "docs(protocol): add /settings and /devices endpoints"
```

---

## Task 8: App — settings + device models

**Files:**
- Create: `app/lib/core/models/agent_settings.dart`
- Create: `app/lib/core/models/device.dart`
- Test: `app/test/models_test.dart` (append)

- [ ] **Step 1: Write the failing test** (append to `models_test.dart`)

```dart
import 'package:remote_file_explorer/core/models/agent_settings.dart';
import 'package:remote_file_explorer/core/models/device.dart';

// ... inside a new group:
  group('AgentSettings', () {
    test('parses and round-trips', () {
      final s = AgentSettings.fromJson({
        'readOnly': true,
        'roots': ['/a', '/b'],
        'agentName': 'pc',
      });
      expect(s.readOnly, isTrue);
      expect(s.roots, ['/a', '/b']);
      expect(s.agentName, 'pc');
    });
  });

  group('Device', () {
    test('parses current flag', () {
      final d = Device.fromJson({
        'id': 'x',
        'label': 'phone',
        'created': 1000,
        'lastSeen': 2000,
        'revoked': false,
        'current': true,
      });
      expect(d.id, 'x');
      expect(d.current, isTrue);
      expect(d.revoked, isFalse);
    });
  });
```

(Confirm the package import prefix matches the existing tests — check the top of `models_test.dart`; the package name is `remote_file_explorer` per `pubspec.yaml`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter test test/models_test.dart`
Expected: FAIL — `agent_settings.dart` not found / `AgentSettings` undefined.

- [ ] **Step 3: Write minimal implementation**

`agent_settings.dart`:
```dart
/// Mirror of the agent's GET/PATCH /v1/settings payload.
class AgentSettings {
  const AgentSettings({
    required this.readOnly,
    required this.roots,
    required this.agentName,
  });

  final bool readOnly;
  final List<String> roots;
  final String agentName;

  factory AgentSettings.fromJson(Map<String, dynamic> json) => AgentSettings(
        readOnly: json['readOnly'] as bool? ?? false,
        roots: (json['roots'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        agentName: json['agentName'] as String? ?? '',
      );

  AgentSettings copyWith({bool? readOnly, List<String>? roots, String? agentName}) =>
      AgentSettings(
        readOnly: readOnly ?? this.readOnly,
        roots: roots ?? this.roots,
        agentName: agentName ?? this.agentName,
      );
}
```

`device.dart`:
```dart
/// A paired device as reported by GET /v1/devices.
class Device {
  const Device({
    required this.id,
    required this.label,
    required this.created,
    required this.lastSeen,
    required this.revoked,
    required this.current,
  });

  final String id;
  final String label;
  final DateTime created;
  final DateTime lastSeen;
  final bool revoked;
  final bool current;

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        created: DateTime.fromMillisecondsSinceEpoch(
            ((json['created'] as num?)?.toInt() ?? 0) * 1000),
        lastSeen: DateTime.fromMillisecondsSinceEpoch(
            ((json['lastSeen'] as num?)?.toInt() ?? 0) * 1000),
        revoked: json['revoked'] as bool? ?? false,
        current: json['current'] as bool? ?? false,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter test test/models_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/models/agent_settings.dart app/lib/core/models/device.dart app/test/models_test.dart
git commit -m "feat(app): AgentSettings and Device models"
```

---

## Task 9: App — AgentClient methods

**Files:**
- Modify: `app/lib/core/api/agent_client.dart` (add imports + methods after `meta`/`search`)

- [ ] **Step 1: Add imports + methods**

Add imports at the top:
```dart
import '../models/agent_settings.dart';
import '../models/device.dart';
```

Add methods (place after `search`, before the write section):
```dart
  // ---------------------------------------------------------------------------
  // Settings & device management
  // ---------------------------------------------------------------------------

  Future<AgentSettings> getSettings() async {
    final data = await _get<Map<String, dynamic>>('/settings');
    return AgentSettings.fromJson(data);
  }

  Future<AgentSettings> updateSettings({
    bool? readOnly,
    List<String>? roots,
    String? agentName,
  }) async {
    final data = await _patch<Map<String, dynamic>>('/settings', data: {
      if (readOnly != null) 'readOnly': readOnly,
      if (roots != null) 'roots': roots,
      if (agentName != null) 'agentName': agentName,
    });
    return AgentSettings.fromJson(data);
  }

  Future<List<Device>> listDevices() async {
    final data = await _get<List<dynamic>>('/devices');
    return data
        .map((e) => Device.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> revokeDevice(String id) async {
    await _delete<void>('/devices/$id');
  }
```

- [ ] **Step 2: Verify it analyzes clean**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter analyze lib/core/api/agent_client.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/core/api/agent_client.dart
git commit -m "feat(app): AgentClient settings + device methods"
```

---

## Task 10: App — Settings screen

**Files:**
- Create: `app/lib/features/settings/settings_screen.dart`
- Modify: `app/lib/features/hosts/host_list_screen.dart` (add overflow menu → Settings)

- [ ] **Step 1: Create `settings_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/agent_settings.dart';
import '../../core/models/device.dart';
import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';

/// Per-host settings: read-only mode, folder jail, paired devices, agent name.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, required this.host});
  final Host host;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AgentClient? _client;
  AgentSettings? _settings;
  List<Device> _devices = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = await ref.read(hostStoreProvider.future);
      final token = await store.getToken(widget.host.id);
      final client = AgentClient(widget.host, deviceToken: token);
      final settings = await client.getSettings();
      final devices = await client.listDevices();
      setState(() {
        _client = client;
        _settings = settings;
        _devices = devices;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _patch({bool? readOnly, List<String>? roots, String? name}) async {
    final client = _client;
    if (client == null) return;
    final prev = _settings;
    // Optimistic update.
    setState(() {
      _settings = _settings?.copyWith(
        readOnly: readOnly,
        roots: roots,
        agentName: name,
      );
    });
    try {
      final updated = await client.updateSettings(
        readOnly: readOnly,
        roots: roots,
        agentName: name,
      );
      setState(() => _settings = updated);
    } catch (e) {
      setState(() => _settings = prev); // rollback
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  Future<void> _revoke(Device d) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.revokeDevice(d.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Revoke failed: $e')));
      }
    }
  }

  Future<void> _addRoot() async {
    final ctrl = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add allowed folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '/home/me/Documents'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (path != null && path.isNotEmpty) {
      final roots = [...?_settings?.roots, path];
      await _patch(roots: roots);
    }
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _settings?.agentName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename agent'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await _patch(name: name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final s = _settings!;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'This phone has full control of the host. Anyone with access '
                'to it can change these settings and reach allowed folders.',
              ),
            ),
          ),
        ),
        ListTile(
          title: const Text('Agent name'),
          subtitle: Text(s.agentName),
          trailing: const Icon(Icons.edit),
          onTap: _editName,
        ),
        SwitchListTile(
          title: const Text('Read-only mode'),
          subtitle: Text(s.readOnly
              ? 'Writes are rejected'
              : 'This phone can modify files'),
          value: s.readOnly,
          onChanged: (v) => _patch(readOnly: v),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Allowed folders',
                  style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                  icon: const Icon(Icons.add), onPressed: _addRoot),
            ],
          ),
        ),
        if (s.roots.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('All folders allowed'),
          )
        else
          ...s.roots.map((r) => ListTile(
                dense: true,
                title: Text(r),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => _patch(
                    roots: s.roots.where((x) => x != r).toList(),
                  ),
                ),
              )),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Paired devices',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        ..._devices.map((d) => ListTile(
              leading: Icon(d.revoked
                  ? Icons.phonelink_erase
                  : Icons.smartphone),
              title: Text(d.current ? '${d.label} (this phone)' : d.label),
              subtitle: Text(d.revoked
                  ? 'Revoked'
                  : 'Last seen ${d.lastSeen.toLocal()}'),
              trailing: (d.current || d.revoked)
                  ? null
                  : TextButton(
                      onPressed: () => _revoke(d),
                      child: const Text('Revoke'),
                    ),
            )),
        const SizedBox(height: 24),
      ],
    );
  }
}
```

- [ ] **Step 2: Add entry point in `host_list_screen.dart`**

In `_HostCard.build`, the trailing currently is `const Icon(Icons.chevron_right)`. Replace it with a `PopupMenuButton` that offers "Open" and "Settings":

```dart
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'open') _openExplorer(context);
                  if (v == 'settings') {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SettingsScreen(host: widget.host),
                    ));
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'open', child: Text('Open')),
                  PopupMenuItem(value: 'settings', child: Text('Settings')),
                ],
              ),
```

Add the import: `import '../settings/settings_screen.dart';`

- [ ] **Step 3: Analyze + build**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter analyze lib/ && flutter build apk --debug`
Expected: `No issues found!` then `✓ Built ... app-debug.apk`.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/settings/settings_screen.dart app/lib/features/hosts/host_list_screen.dart
git commit -m "feat(app): per-host settings screen (read-only, jail, devices, rename)"
```

---

## Pillar A Verification (run after all tasks)

- [ ] `cd agent && go test ./...` — all green.
- [ ] Live read-only: PATCH `readOnly:true` from the app → a create/delete is rejected with a clear message; toggle off → write works. No agent restart.
- [ ] Jail: add a root that excludes `/tmp`; browsing `/tmp` fails; remove it → works.
- [ ] Devices: the current phone shows "(this phone)" and has no Revoke; revoke a second device → its next request 401s; self-revoke attempt → 409 (no Revoke button is shown, but the API enforces it).
- [ ] Rename agent → host card / health reflect the new name.
