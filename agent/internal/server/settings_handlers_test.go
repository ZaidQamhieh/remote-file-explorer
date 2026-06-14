package server

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
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

// newTestDepsWithRoots is like newTestDeps but seeds the agent's configured
// global roots, for tests that need to validate a jailRoot against them.
func newTestDepsWithRoots(t *testing.T, roots []string) (*store.DB, *settings.Store) {
	t.Helper()
	db, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatalf("store: %v", err)
	}
	t.Cleanup(func() { db.Close() })
	st, err := settings.Load(db, false, roots, "test-pc")
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
	_ = db.TouchDevice("id-keep", "192.168.1.42", "1.10.0+18")

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

	// The keeper's row reflects its recorded address/version; the untouched
	// device's row has the empty-string defaults.
	var keeper, goneRow map[string]any
	for _, d := range list {
		switch d["id"] {
		case "id-keep":
			keeper = d
		case "id-gone":
			goneRow = d
		}
	}
	if keeper == nil || keeper["lastAddress"] != "192.168.1.42" || keeper["lastVersion"] != "1.10.0+18" {
		t.Fatalf("expected keeper lastAddress/lastVersion recorded, got %v", keeper)
	}
	if goneRow == nil || goneRow["lastAddress"] != "" || goneRow["lastVersion"] != "" {
		t.Fatalf("expected gone device to have empty lastAddress/lastVersion, got %v", goneRow)
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

// patchDeviceJail builds and executes a PATCH /v1/devices/{id} request
// against setDeviceJailHandler directly, returning the recorder.
func patchDeviceJail(t *testing.T, db *store.DB, st settingsRootsView, id string, jailRoot *string) *httptest.ResponseRecorder {
	t.Helper()
	var body string
	if jailRoot == nil {
		body = `{}`
	} else {
		b, _ := json.Marshal(map[string]string{"jailRoot": *jailRoot})
		body = string(b)
	}
	req := httptest.NewRequest(http.MethodPatch, "/v1/devices/"+id, strings.NewReader(body))
	req = withURLParam(req, map[string]string{"id": id})
	rr := httptest.NewRecorder()
	setDeviceJailHandler(db, st)(rr, req)
	return rr
}

// TestSetDeviceJailHandler_SetAndClear verifies PATCH /v1/devices/{id} sets a
// jailRoot that resolves within the agent's configured global roots, returns
// the updated Device JSON (with jailRoot populated), persists it (visible via
// GetDeviceByID), and that an empty jailRoot clears it again.
func TestSetDeviceJailHandler_SetAndClear(t *testing.T) {
	root := t.TempDir()
	db, st := newTestDepsWithRoots(t, []string{root})
	if err := db.CreateDevice("id-1", "phone-a", "tok-a"); err != nil {
		t.Fatalf("create: %v", err)
	}

	sub := filepath.Join(root, "shared")
	if err := os.MkdirAll(sub, 0o755); err != nil {
		t.Fatalf("mkdir sub: %v", err)
	}

	// Set a valid jail within the global root.
	rr := patchDeviceJail(t, db, st, "id-1", &sub)
	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}
	var got map[string]any
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got["jailRoot"] != sub {
		t.Fatalf("expected jailRoot %q in response, got %v", sub, got["jailRoot"])
	}

	// Persisted.
	d, err := db.GetDeviceByID("id-1")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if d == nil || d.JailRoot != sub {
		t.Fatalf("expected persisted JailRoot %q, got %+v", sub, d)
	}

	// Clear it.
	empty := ""
	rr2 := patchDeviceJail(t, db, st, "id-1", &empty)
	if rr2.Code != http.StatusOK {
		t.Fatalf("expected 200 clearing jail, got %d: %s", rr2.Code, rr2.Body.String())
	}
	var got2 map[string]any
	if err := json.Unmarshal(rr2.Body.Bytes(), &got2); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got2["jailRoot"] != "" {
		t.Fatalf("expected jailRoot cleared in response, got %v", got2["jailRoot"])
	}
	d2, err := db.GetDeviceByID("id-1")
	if err != nil {
		t.Fatalf("get after clear: %v", err)
	}
	if d2 == nil || d2.JailRoot != "" {
		t.Fatalf("expected persisted JailRoot cleared, got %+v", d2)
	}
}

// TestSetDeviceJailHandler_OutsideGlobalRootsRejected verifies that an admin
// cannot widen a device's access by setting a jailRoot outside the agent's
// configured global roots: the handler must reject it with 400 (code
// INVALID) and leave the device's jailRoot unchanged.
func TestSetDeviceJailHandler_OutsideGlobalRootsRejected(t *testing.T) {
	root := t.TempDir()
	outside := t.TempDir()
	db, st := newTestDepsWithRoots(t, []string{root})
	if err := db.CreateDevice("id-1", "phone-a", "tok-a"); err != nil {
		t.Fatalf("create: %v", err)
	}

	rr := patchDeviceJail(t, db, st, "id-1", &outside)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rr.Code, rr.Body.String())
	}
	var got apiError
	_ = json.Unmarshal(rr.Body.Bytes(), &got)
	if got.Code != "INVALID" {
		t.Fatalf("expected INVALID error code, got %+v", got)
	}

	// jailRoot must remain unset.
	d, err := db.GetDeviceByID("id-1")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if d == nil || d.JailRoot != "" {
		t.Fatalf("expected jailRoot to remain empty after rejection, got %+v", d)
	}
}

// TestSetDeviceJailHandler_NonAbsoluteRejected verifies a relative jailRoot
// is rejected with 400 INVALID.
func TestSetDeviceJailHandler_NonAbsoluteRejected(t *testing.T) {
	db, st := newTestDepsWithRoots(t, nil)
	if err := db.CreateDevice("id-1", "phone-a", "tok-a"); err != nil {
		t.Fatalf("create: %v", err)
	}

	rel := "relative/path"
	rr := patchDeviceJail(t, db, st, "id-1", &rel)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rr.Code, rr.Body.String())
	}
	var got apiError
	_ = json.Unmarshal(rr.Body.Bytes(), &got)
	if got.Code != "INVALID" {
		t.Fatalf("expected INVALID error code, got %+v", got)
	}
}

// TestSetDeviceJailHandler_NoGlobalRootsAllowsAnyAbsolutePath verifies that
// when the agent has NO configured global roots (open access), any absolute
// jailRoot is accepted — there is nothing to validate containment against,
// and a per-device jail in this case can only narrow access.
func TestSetDeviceJailHandler_NoGlobalRootsAllowsAnyAbsolutePath(t *testing.T) {
	db, st := newTestDepsWithRoots(t, nil)
	if err := db.CreateDevice("id-1", "phone-a", "tok-a"); err != nil {
		t.Fatalf("create: %v", err)
	}

	anyAbs := t.TempDir()
	rr := patchDeviceJail(t, db, st, "id-1", &anyAbs)
	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}
	d, err := db.GetDeviceByID("id-1")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if d == nil || d.JailRoot != filepath.Clean(anyAbs) {
		t.Fatalf("expected JailRoot set to %q, got %+v", anyAbs, d)
	}
}

// TestSetDeviceJailHandler_MissingBodyRejected verifies a request with no
// jailRoot field is rejected with 400 BAD_REQUEST (not silently treated as
// "clear").
func TestSetDeviceJailHandler_MissingBodyRejected(t *testing.T) {
	db, st := newTestDepsWithRoots(t, nil)
	if err := db.CreateDevice("id-1", "phone-a", "tok-a"); err != nil {
		t.Fatalf("create: %v", err)
	}

	rr := patchDeviceJail(t, db, st, "id-1", nil)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rr.Code, rr.Body.String())
	}
}

// TestDeviceJailMiddleware_NarrowsOpsForJailedDevice verifies the
// post-auth middleware: a device with a non-empty JailRoot gets a
// per-request *fsops.Ops (via opsCtxKey/opsFromContext) narrowed to its
// jail, so a downstream handler resolving a path outside that jail (but
// inside the agent's global root) is rejected with FORBIDDEN — while a
// device with NO jailRoot continues to use the shared base ops unchanged.
func TestDeviceJailMiddleware_NarrowsOpsForJailedDevice(t *testing.T) {
	root := t.TempDir()
	sub := filepath.Join(root, "jailed")
	sibling := filepath.Join(root, "sibling")
	if err := os.MkdirAll(sub, 0o755); err != nil {
		t.Fatalf("mkdir sub: %v", err)
	}
	if err := os.MkdirAll(sibling, 0o755); err != nil {
		t.Fatalf("mkdir sibling: %v", err)
	}
	if err := os.WriteFile(filepath.Join(sibling, "secret.txt"), []byte("secret"), 0o644); err != nil {
		t.Fatalf("write secret: %v", err)
	}

	db, st := newTestDepsWithRoots(t, []string{root})
	baseOps := fsops.NewWithSettings(st)

	// A jailed device, confined to root/jailed.
	if err := db.CreateDevice("id-jailed", "jailed-phone", "tok-jailed"); err != nil {
		t.Fatalf("create jailed: %v", err)
	}
	if err := db.SetDeviceJail("id-jailed", sub); err != nil {
		t.Fatalf("set jail: %v", err)
	}
	jailedDevice, err := db.DeviceByToken("tok-jailed")
	if err != nil || jailedDevice == nil {
		t.Fatalf("device by token: %v", err)
	}

	// An unrestricted device.
	if err := db.CreateDevice("id-open", "open-phone", "tok-open"); err != nil {
		t.Fatalf("create open: %v", err)
	}
	openDevice, err := db.DeviceByToken("tok-open")
	if err != nil || openDevice == nil {
		t.Fatalf("device by token: %v", err)
	}

	// downstream is the handler under test: it resolves "path" through the
	// per-request ops from context, reporting FORBIDDEN vs OK.
	downstream := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		effectiveOps := opsFromContext(r.Context(), baseOps)
		path := r.URL.Query().Get("path")
		if _, err := effectiveOps.Resolve(path); err != nil {
			writeError(w, http.StatusForbidden, "FORBIDDEN", err.Error())
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	chain := deviceJailMiddleware(baseOps)(downstream)

	// Jailed device: a sibling path (inside the global root, outside the
	// device jail) is FORBIDDEN.
	req := httptest.NewRequest(http.MethodGet, "/v1/fs?path="+filepath.Join(sibling, "secret.txt"), nil)
	req = req.WithContext(withDevice(req.Context(), jailedDevice))
	rr := httptest.NewRecorder()
	chain.ServeHTTP(rr, req)
	if rr.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for jailed device accessing sibling path, got %d: %s", rr.Code, rr.Body.String())
	}

	// Jailed device: a path inside its own jail is OK.
	req2 := httptest.NewRequest(http.MethodGet, "/v1/fs?path="+filepath.Join(sub, "file.txt"), nil)
	req2 = req2.WithContext(withDevice(req2.Context(), jailedDevice))
	rr2 := httptest.NewRecorder()
	chain.ServeHTTP(rr2, req2)
	if rr2.Code != http.StatusOK {
		t.Fatalf("expected 200 for jailed device accessing its own jail, got %d: %s", rr2.Code, rr2.Body.String())
	}

	// Unrestricted device: the same sibling path is OK (no regression).
	req3 := httptest.NewRequest(http.MethodGet, "/v1/fs?path="+filepath.Join(sibling, "secret.txt"), nil)
	req3 = req3.WithContext(withDevice(req3.Context(), openDevice))
	rr3 := httptest.NewRecorder()
	chain.ServeHTTP(rr3, req3)
	if rr3.Code != http.StatusOK {
		t.Fatalf("expected 200 for unrestricted device accessing sibling path, got %d: %s", rr3.Code, rr3.Body.String())
	}
}
