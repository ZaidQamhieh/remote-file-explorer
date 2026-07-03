package server

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/pairing"
)

func TestRegisterHandler_RequiresValidPairingCode(t *testing.T) {
	db, _ := newTestDeps(t)
	pm := pairing.New(db, "127.0.0.1:8765", "", "fingerprint")
	cfg := Config{Name: "test-pc"}
	handler := registerHandler(cfg, db, pm, newNonceStore())

	body := `{"pairingCode":"WRONGCODE","username":"owner","password":"correct-horse-battery"}`
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/register", strings.NewReader(body))
	handler(rr, req)
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d: %s", rr.Code, rr.Body.String())
	}
}

func TestRegisterHandler_WeakPasswordRejected(t *testing.T) {
	db, _ := newTestDeps(t)
	pm := pairing.New(db, "127.0.0.1:8765", "", "fingerprint")
	cfg := Config{Name: "test-pc"}
	handler := registerHandler(cfg, db, pm, newNonceStore())

	code, _, err := pm.Mint(time.Minute)
	if err != nil {
		t.Fatalf("mint: %v", err)
	}

	body := `{"pairingCode":"` + code + `","username":"owner","password":"short"}`
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/register", strings.NewReader(body))
	handler(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rr.Code, rr.Body.String())
	}
}

func TestRegisterHandler_ValidRegistrationCreatesAccountAndDevice(t *testing.T) {
	db, _ := newTestDeps(t)
	pm := pairing.New(db, "127.0.0.1:8765", "10.0.0.1", "sha256-fp")
	cfg := Config{
		Name:             "test-pc",
		CertFingerprint:  "sha256-fp",
		Address:          "127.0.0.1:8765",
		TailscaleAddress: "10.0.0.1",
	}
	nonces := newNonceStore()
	handler := registerHandler(cfg, db, pm, nonces)

	code, _, err := pm.Mint(time.Minute)
	if err != nil {
		t.Fatalf("mint: %v", err)
	}
	pubKey, nonce, sig := signedDeviceProof(t, nonces)

	body := `{"pairingCode":"` + code + `","username":"owner","password":"correct-horse-battery",` +
		`"deviceLabel":"my-phone","deviceId":"android-123",` +
		`"devicePublicKey":"` + pubKey + `","nonce":"` + nonce + `","signature":"` + sig + `"}`
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/register", strings.NewReader(body))
	handler(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}
	var resp pairResponse
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.DeviceToken == "" || resp.DeviceID == "" {
		t.Fatalf("expected token+deviceID, got %+v", resp)
	}

	user, err := db.GetUserByUsername("owner")
	if err != nil || user == nil {
		t.Fatalf("expected account to be created: %v", err)
	}

	// The same pairing code can't be reused for a second registration.
	body2 := `{"pairingCode":"` + code + `","username":"someone-else","password":"correct-horse-battery"}`
	rr2 := httptest.NewRecorder()
	req2 := httptest.NewRequest(http.MethodPost, "/v1/register", strings.NewReader(body2))
	handler(rr2, req2)
	if rr2.Code != http.StatusUnauthorized {
		t.Fatalf("expected reused pairing code to be rejected, got %d", rr2.Code)
	}
}

func TestRegisterHandler_DuplicateUsernameRejected(t *testing.T) {
	db, _ := newTestDeps(t)
	pm := pairing.New(db, "127.0.0.1:8765", "", "fingerprint")
	cfg := Config{Name: "test-pc"}
	nonces := newNonceStore()
	handler := registerHandler(cfg, db, pm, nonces)

	code1, _, _ := pm.Mint(time.Minute)
	pubKey1, nonce1, sig1 := signedDeviceProof(t, nonces)
	body1 := `{"pairingCode":"` + code1 + `","username":"owner","password":"correct-horse-battery",` +
		`"devicePublicKey":"` + pubKey1 + `","nonce":"` + nonce1 + `","signature":"` + sig1 + `"}`
	rr1 := httptest.NewRecorder()
	req1 := httptest.NewRequest(http.MethodPost, "/v1/register", strings.NewReader(body1))
	handler(rr1, req1)
	if rr1.Code != http.StatusOK {
		t.Fatalf("first registration expected 200, got %d: %s", rr1.Code, rr1.Body.String())
	}

	code2, _, _ := pm.Mint(time.Minute)
	pubKey2, nonce2, sig2 := signedDeviceProof(t, nonces)
	body2 := `{"pairingCode":"` + code2 + `","username":"owner","password":"another-password",` +
		`"devicePublicKey":"` + pubKey2 + `","nonce":"` + nonce2 + `","signature":"` + sig2 + `"}`
	rr2 := httptest.NewRecorder()
	req2 := httptest.NewRequest(http.MethodPost, "/v1/register", strings.NewReader(body2))
	handler(rr2, req2)
	if rr2.Code != http.StatusConflict {
		t.Fatalf("expected 409 for duplicate username, got %d: %s", rr2.Code, rr2.Body.String())
	}
}
