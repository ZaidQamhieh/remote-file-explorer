package server

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/pairing"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/security"
)

func TestChallengeHandler_MintsSingleUseNonce(t *testing.T) {
	nonces := newNonceStore()
	handler := challengeHandler(nonces)

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/auth/challenge", nil)
	handler(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}
	var resp map[string]string
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp["nonce"] == "" {
		t.Fatal("expected a non-empty nonce")
	}
	if !nonces.Consume(resp["nonce"]) {
		t.Fatal("freshly minted nonce should be consumable once")
	}
	if nonces.Consume(resp["nonce"]) {
		t.Fatal("nonce should not be consumable twice")
	}
}

// TestLoginHandler_DeviceKeyMismatchRejected verifies that a device id
// already pinned to one Ed25519 key can't mint a new token by presenting a
// different key — the point of pinning (see verifyDeviceProof).
func TestLoginHandler_DeviceKeyMismatchRejected(t *testing.T) {
	db, _ := newTestDeps(t)
	hash, err := security.HashPassword("correct-horse-battery")
	if err != nil {
		t.Fatalf("hash: %v", err)
	}
	if err := db.CreateUser("owner", hash); err != nil {
		t.Fatalf("create user: %v", err)
	}
	cfg := Config{Name: "test-pc"}
	nonces := newNonceStore()
	handler := loginHandler(cfg, db, nonces)

	// First login pins a key to device id "android-123".
	pubKey1, nonce1, sig1 := signedDeviceProof(t, nonces)
	body1 := `{"username":"owner","password":"correct-horse-battery","deviceId":"android-123",` +
		`"devicePublicKey":"` + pubKey1 + `","nonce":"` + nonce1 + `","signature":"` + sig1 + `"}`
	rr1 := httptest.NewRecorder()
	req1 := httptest.NewRequest(http.MethodPost, "/v1/login", strings.NewReader(body1))
	handler(rr1, req1)
	if rr1.Code != http.StatusOK {
		t.Fatalf("first login expected 200, got %d: %s", rr1.Code, rr1.Body.String())
	}

	// A second login for the SAME device id but a DIFFERENT key must be rejected.
	pubKey2, nonce2, sig2 := signedDeviceProof(t, nonces)
	body2 := `{"username":"owner","password":"correct-horse-battery","deviceId":"android-123",` +
		`"devicePublicKey":"` + pubKey2 + `","nonce":"` + nonce2 + `","signature":"` + sig2 + `"}`
	rr2 := httptest.NewRecorder()
	req2 := httptest.NewRequest(http.MethodPost, "/v1/login", strings.NewReader(body2))
	handler(rr2, req2)
	if rr2.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 on key mismatch, got %d: %s", rr2.Code, rr2.Body.String())
	}
	var got apiError
	if err := json.Unmarshal(rr2.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode error body: %v", err)
	}
	if got.Code != "DEVICE_KEY_MISMATCH" {
		t.Fatalf("unexpected error code: %+v", got)
	}
}

func TestLoginHandler_InvalidSignatureRejected(t *testing.T) {
	db, _ := newTestDeps(t)
	hash, err := security.HashPassword("correct-horse-battery")
	if err != nil {
		t.Fatalf("hash: %v", err)
	}
	if err := db.CreateUser("owner", hash); err != nil {
		t.Fatalf("create user: %v", err)
	}
	cfg := Config{Name: "test-pc"}
	nonces := newNonceStore()
	handler := loginHandler(cfg, db, nonces)

	pubKey, _, _ := signedDeviceProof(t, nonces)
	nonce, err := nonces.Mint()
	if err != nil {
		t.Fatalf("mint: %v", err)
	}
	body := `{"username":"owner","password":"correct-horse-battery",` +
		`"devicePublicKey":"` + pubKey + `","nonce":"` + nonce + `","signature":"bm90LWEtcmVhbC1zaWduYXR1cmU="}`
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/login", strings.NewReader(body))
	handler(rr, req)
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d: %s", rr.Code, rr.Body.String())
	}
	var got apiError
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode error body: %v", err)
	}
	if got.Code != "INVALID_SIGNATURE" {
		t.Fatalf("unexpected error code: %+v", got)
	}
}

func TestLoginHandler_MissingDeviceProofRejected(t *testing.T) {
	db, _ := newTestDeps(t)
	hash, err := security.HashPassword("correct-horse-battery")
	if err != nil {
		t.Fatalf("hash: %v", err)
	}
	if err := db.CreateUser("owner", hash); err != nil {
		t.Fatalf("create user: %v", err)
	}
	cfg := Config{Name: "test-pc"}
	handler := loginHandler(cfg, db, newNonceStore())

	body := `{"username":"owner","password":"correct-horse-battery"}`
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/login", strings.NewReader(body))
	handler(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rr.Code, rr.Body.String())
	}
	var got apiError
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode error body: %v", err)
	}
	if got.Code != "DEVICE_KEY_REQUIRED" {
		t.Fatalf("unexpected error code: %+v", got)
	}
}

// TestPairHandler_KeyChangeRePinsRatherThanRejects verifies pairing (unlike
// login) accepts a device id presenting a *different* key than what's
// pinned — consuming a fresh one-time code is itself a strong trust event
// (physical access to the host), covering a legitimate reinstall that
// generated a new device key. See verifyDeviceProof's enforceKeyPin doc.
func TestPairHandler_KeyChangeRePinsRatherThanRejects(t *testing.T) {
	db, _ := newTestDeps(t)
	pm := pairing.New(db, "127.0.0.1:8765", "", "fingerprint")
	cfg := Config{Name: "test-pc"}
	nonces := newNonceStore()
	handler := pairHandler(cfg, db, pm, nonces)

	// First pairing pins a key to device id "android-123".
	code1, _, err := pm.Mint(time.Minute)
	if err != nil {
		t.Fatalf("mint: %v", err)
	}
	pubKey1, nonce1, sig1 := signedDeviceProof(t, nonces)
	body1 := `{"pairingCode":"` + code1 + `","deviceLabel":"phone","deviceId":"android-123",` +
		`"devicePublicKey":"` + pubKey1 + `","nonce":"` + nonce1 + `","signature":"` + sig1 + `"}`
	rr1 := httptest.NewRecorder()
	req1 := httptest.NewRequest(http.MethodPost, "/v1/pair", strings.NewReader(body1))
	handler(rr1, req1)
	if rr1.Code != http.StatusOK {
		t.Fatalf("first pairing expected 200, got %d: %s", rr1.Code, rr1.Body.String())
	}

	// Re-pairing the SAME device id with a fresh one-time code and a
	// DIFFERENT key (simulating a reinstall) must succeed, re-pinning the
	// new key rather than rejecting.
	code2, _, err := pm.Mint(time.Minute)
	if err != nil {
		t.Fatalf("mint: %v", err)
	}
	pubKey2, nonce2, sig2 := signedDeviceProof(t, nonces)
	if pubKey2 == pubKey1 {
		t.Fatal("test setup: expected a different key on the second pairing")
	}
	body2 := `{"pairingCode":"` + code2 + `","deviceLabel":"phone","deviceId":"android-123",` +
		`"devicePublicKey":"` + pubKey2 + `","nonce":"` + nonce2 + `","signature":"` + sig2 + `"}`
	rr2 := httptest.NewRecorder()
	req2 := httptest.NewRequest(http.MethodPost, "/v1/pair", strings.NewReader(body2))
	handler(rr2, req2)
	if rr2.Code != http.StatusOK {
		t.Fatalf("re-pairing with a new key expected 200, got %d: %s", rr2.Code, rr2.Body.String())
	}

	pinned, err := db.DevicePublicKeyByClientID("android-123")
	if err != nil {
		t.Fatalf("DevicePublicKeyByClientID: %v", err)
	}
	if pinned != pubKey2 {
		t.Fatalf("expected the pinned key to be updated to the new key, got %q want %q", pinned, pubKey2)
	}
}
