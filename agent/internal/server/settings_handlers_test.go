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
