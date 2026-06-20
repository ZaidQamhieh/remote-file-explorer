package server

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/settings"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

func newAuthTestDeps(t *testing.T) (*store.DB, *settings.Store, string) {
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
	token := "test-token-abc123"
	if err := db.CreateDevice("dev1", "phone1", token); err != nil {
		t.Fatalf("create device: %v", err)
	}
	return db, st, token
}

func okHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
}

func TestAuthMiddleware_MissingHeader(t *testing.T) {
	db, _, _ := newAuthTestDeps(t)
	handler := authMiddleware(db)(okHandler())

	req := httptest.NewRequest(http.MethodGet, "/v1/fs", nil)
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rr.Code)
	}
}

func TestAuthMiddleware_InvalidFormat(t *testing.T) {
	db, _, _ := newAuthTestDeps(t)
	handler := authMiddleware(db)(okHandler())

	req := httptest.NewRequest(http.MethodGet, "/v1/fs", nil)
	req.Header.Set("Authorization", "Basic abc123")
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rr.Code)
	}
}

func TestAuthMiddleware_InvalidToken(t *testing.T) {
	db, _, _ := newAuthTestDeps(t)
	handler := authMiddleware(db)(okHandler())

	req := httptest.NewRequest(http.MethodGet, "/v1/fs", nil)
	req.Header.Set("Authorization", "Bearer wrong-token")
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rr.Code)
	}
}

func TestAuthMiddleware_ValidToken(t *testing.T) {
	db, _, token := newAuthTestDeps(t)
	handler := authMiddleware(db)(okHandler())

	req := httptest.NewRequest(http.MethodGet, "/v1/fs", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}
}

func TestAuthMiddleware_RevokedToken(t *testing.T) {
	db, _, token := newAuthTestDeps(t)
	if err := db.RevokeDevice("dev1"); err != nil {
		t.Fatalf("revoke: %v", err)
	}
	handler := authMiddleware(db)(okHandler())

	req := httptest.NewRequest(http.MethodGet, "/v1/fs", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rr.Code)
	}
}

func TestAuthMiddleware_SetsDeviceContext(t *testing.T) {
	db, _, token := newAuthTestDeps(t)
	var gotDevice *store.Device
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotDevice = r.Context().Value(deviceCtxKey).(*store.Device)
		w.WriteHeader(http.StatusOK)
	})
	handler := authMiddleware(db)(inner)

	req := httptest.NewRequest(http.MethodGet, "/v1/fs", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}
	if gotDevice == nil || gotDevice.ID != "dev1" {
		t.Fatalf("expected device dev1 in context, got %+v", gotDevice)
	}
}

func TestDeviceJailMiddleware_NoJail(t *testing.T) {
	root := t.TempDir()
	ops := fsops.New([]string{root}, false)
	device := &store.Device{ID: "d1"}

	var gotOps *fsops.Ops
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotOps = opsFromContext(r.Context(), ops)
		w.WriteHeader(http.StatusOK)
	})
	handler := deviceJailMiddleware(ops)(inner)

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	ctx := context.WithValue(req.Context(), deviceCtxKey, device)
	req = req.WithContext(ctx)
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if gotOps == nil {
		t.Fatal("expected ops in context")
	}
}

func TestDeviceJailMiddleware_ReadOnly(t *testing.T) {
	root := t.TempDir()
	ops := fsops.New([]string{root}, false)
	device := &store.Device{ID: "d1", ReadOnly: true}

	var gotOps *fsops.Ops
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotOps = opsFromContext(r.Context(), ops)
		w.WriteHeader(http.StatusOK)
	})
	handler := deviceJailMiddleware(ops)(inner)

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	ctx := context.WithValue(req.Context(), deviceCtxKey, device)
	req = req.WithContext(ctx)
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if gotOps == nil {
		t.Fatal("expected ops in context")
	}
	// Verify read-only by attempting a write operation.
	_, err := gotOps.CreateFolder(root + "/test-dir")
	if err == nil {
		t.Fatal("expected error from read-only ops")
	}
}
