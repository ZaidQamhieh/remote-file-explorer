package server

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestMintShareHandler_ForbiddenWhenDisabled(t *testing.T) {
	ops, root := newFsFixture(t)
	db, st := newTestDeps(t) // AllowSharing defaults false
	cfg := Config{Address: "127.0.0.1:8765", Settings: st}
	handler := mintShareHandler(cfg, db, ops)

	body := `{"path":"` + filepath.Join(root, "a.txt") + `"}`
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/share/mint", strings.NewReader(body))
	handler(rr, req)
	if rr.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d: %s", rr.Code, rr.Body.String())
	}
}

func TestMintShareHandler_RejectsDirectory(t *testing.T) {
	ops, root := newFsFixture(t)
	db, st := newTestDeps(t)
	if err := st.SetAllowSharing(true); err != nil {
		t.Fatalf("enable sharing: %v", err)
	}
	cfg := Config{Address: "127.0.0.1:8765", Settings: st}
	handler := mintShareHandler(cfg, db, ops)

	body := `{"path":"` + root + `"}`
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/share/mint", strings.NewReader(body))
	handler(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rr.Code, rr.Body.String())
	}
}

func TestMintShareHandler_Success(t *testing.T) {
	ops, root := newFsFixture(t)
	db, st := newTestDeps(t)
	if err := st.SetAllowSharing(true); err != nil {
		t.Fatalf("enable sharing: %v", err)
	}
	cfg := Config{Address: "127.0.0.1:8765", Settings: st}
	handler := mintShareHandler(cfg, db, ops)

	body := `{"path":"` + filepath.Join(root, "a.txt") + `"}`
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/share/mint", strings.NewReader(body))
	handler(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}

	var resp mintShareResponse
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Token == "" || resp.TokenHash == "" {
		t.Fatalf("expected token+tokenHash, got %+v", resp)
	}
	if resp.TokenHash != hashShareToken(resp.Token) {
		t.Fatalf("tokenHash should be sha256(token)")
	}
	if !strings.Contains(resp.URL, resp.Token) || !strings.Contains(resp.URL, "127.0.0.1:8765") {
		t.Fatalf("unexpected url: %s", resp.URL)
	}
	if resp.ExpiresAt <= time.Now().Unix() {
		t.Fatalf("expected expiresAt in the future, got %d", resp.ExpiresAt)
	}

	// Listing reflects the freshly minted (active) token.
	tokens, err := db.ListShareTokens()
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(tokens) != 1 || tokens[0].TokenHash != resp.TokenHash {
		t.Fatalf("expected the minted token listed, got %+v", tokens)
	}
}

func TestMintShareHandler_RejectsOversizedFile(t *testing.T) {
	ops, root := newFsFixture(t)
	db, st := newTestDeps(t)
	if err := st.SetAllowSharing(true); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, "large.bin")
	if err := os.WriteFile(path, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Truncate(path, shareMaxFileBytes+1); err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/share/mint", strings.NewReader(`{"path":"`+path+`"}`))
	mintShareHandler(Config{Address: "127.0.0.1:8765", Settings: st}, db, ops)(rr, req)
	if rr.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("expected 413, got %d: %s", rr.Code, rr.Body.String())
	}
}

func TestServeShareHandler_UnknownToken404s(t *testing.T) {
	ops, _ := newFsFixture(t)
	db, _ := newTestDeps(t)

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/share/nope", nil)
	req = withURLParam(req, map[string]string{"token": "nope"})
	serveShareHandler(db, ops)(rr, req)
	if rr.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d: %s", rr.Code, rr.Body.String())
	}
}

func TestServeShareHandler_ExpiredToken404s(t *testing.T) {
	ops, root := newFsFixture(t)
	db, _ := newTestDeps(t)

	hash := hashShareToken("expired-token")
	if err := db.CreateShareToken(hash, filepath.Join(root, "a.txt"), time.Now().Add(-time.Minute)); err != nil {
		t.Fatalf("create: %v", err)
	}

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/share/expired-token", nil)
	req = withURLParam(req, map[string]string{"token": "expired-token"})
	serveShareHandler(db, ops)(rr, req)
	if rr.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for expired token, got %d: %s", rr.Code, rr.Body.String())
	}
}

// TestServeShareHandler_SingleUse verifies the first fetch serves the file
// and the second fetch of the SAME token 404s (T1/T6: single-use).
func TestServeShareHandler_SingleUse(t *testing.T) {
	ops, root := newFsFixture(t)
	db, _ := newTestDeps(t)
	handler := serveShareHandler(db, ops)

	hash := hashShareToken("good-token")
	if err := db.CreateShareToken(hash, filepath.Join(root, "a.txt"), time.Now().Add(time.Hour)); err != nil {
		t.Fatalf("create: %v", err)
	}

	rr1 := httptest.NewRecorder()
	req1 := httptest.NewRequest(http.MethodGet, "/v1/share/good-token", nil)
	req1 = withURLParam(req1, map[string]string{"token": "good-token"})
	handler(rr1, req1)
	if rr1.Code != http.StatusOK {
		t.Fatalf("expected 200 on first fetch, got %d: %s", rr1.Code, rr1.Body.String())
	}
	if rr1.Body.String() != "hello" {
		t.Fatalf("expected file content %q, got %q", "hello", rr1.Body.String())
	}

	rr2 := httptest.NewRecorder()
	req2 := httptest.NewRequest(http.MethodGet, "/v1/share/good-token", nil)
	req2 = withURLParam(req2, map[string]string{"token": "good-token"})
	handler(rr2, req2)
	if rr2.Code != http.StatusNotFound {
		t.Fatalf("expected 404 on second fetch (single-use), got %d", rr2.Code)
	}
}

func TestServeShareHandler_MissingTargetDoesNotConsumeToken(t *testing.T) {
	ops, root := newFsFixture(t)
	db, _ := newTestDeps(t)
	handler := serveShareHandler(db, ops)
	path := filepath.Join(root, "created-later.txt")
	hash := hashShareToken("retry-token")
	if err := db.CreateShareToken(hash, path, time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}

	first := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/share/retry-token", nil)
	req = withURLParam(req, map[string]string{"token": "retry-token"})
	handler(first, req)
	if first.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d: %s", first.Code, first.Body.String())
	}
	if _, ok, err := db.LookupShareToken(hash); err != nil || !ok {
		t.Fatalf("missing target consumed token: ok=%v err=%v", ok, err)
	}

	if err := os.WriteFile(path, []byte("available now"), 0o600); err != nil {
		t.Fatal(err)
	}
	second := httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/v1/share/retry-token", nil)
	req = withURLParam(req, map[string]string{"token": "retry-token"})
	handler(second, req)
	if second.Code != http.StatusOK || second.Body.String() != "available now" {
		t.Fatalf("retry = %d %q", second.Code, second.Body.String())
	}
}

func TestRevokeShareHandler(t *testing.T) {
	db, _ := newTestDeps(t)
	hash := hashShareToken("to-revoke")
	if err := db.CreateShareToken(hash, "/tmp/x", time.Now().Add(time.Hour)); err != nil {
		t.Fatalf("create: %v", err)
	}

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodDelete, "/v1/share/"+hash, nil)
	req = withURLParam(req, map[string]string{"tokenHash": hash})
	req = asAdmin(t, db, req)
	revokeShareHandler(db)(rr, req)
	if rr.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d: %s", rr.Code, rr.Body.String())
	}

	tokens, err := db.ListShareTokens()
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(tokens) != 0 {
		t.Fatalf("expected token revoked, got %+v", tokens)
	}
}

func TestRevokeShareHandler_AdminOnly(t *testing.T) {
	db, _ := newTestDeps(t)
	hash := hashShareToken("keep")
	if err := db.CreateShareToken(hash, "/tmp/x", time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if err := db.CreateDevice("phone", "phone", "phone-token"); err != nil {
		t.Fatal(err)
	}
	phone, _ := db.DeviceByToken("phone-token")
	req := httptest.NewRequest(http.MethodDelete, "/v1/share/"+hash, nil)
	req = withURLParam(req, map[string]string{"tokenHash": hash})
	req = req.WithContext(withDevice(req.Context(), phone))
	rr := httptest.NewRecorder()

	revokeShareHandler(db)(rr, req)

	if rr.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d: %s", rr.Code, rr.Body.String())
	}
	if tokens, err := db.ListShareTokens(); err != nil || len(tokens) != 1 {
		t.Fatalf("non-admin revoked share: tokens=%v err=%v", tokens, err)
	}
}
