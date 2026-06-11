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

// TestPairHandler_RateLimitedAfterTooManyAttempts verifies /v1/pair returns
// 429 once more than pairRateLimitAttempts requests land within the window,
// regardless of whether the supplied pairing codes are valid.
func TestPairHandler_RateLimitedAfterTooManyAttempts(t *testing.T) {
	db, _ := newTestDeps(t)
	pm := pairing.New(db, "127.0.0.1:8765", "", "fingerprint")
	cfg := Config{Name: "test-pc"}
	handler := pairHandler(cfg, db, pm)

	body := `{"pairingCode":"WRONGCODE","deviceLabel":"phone"}`

	// First pairRateLimitAttempts requests are not rate-limited (they fail
	// with 401 INVALID_CODE since the code is bogus).
	for i := 0; i < pairRateLimitAttempts; i++ {
		rr := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/v1/pair", strings.NewReader(body))
		handler(rr, req)
		if rr.Code != http.StatusUnauthorized {
			t.Fatalf("attempt %d: expected 401, got %d: %s", i+1, rr.Code, rr.Body.String())
		}
	}

	// The next attempt exceeds the limit and should be rejected with 429.
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/pair", strings.NewReader(body))
	handler(rr, req)
	if rr.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d: %s", rr.Code, rr.Body.String())
	}
	var got apiError
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode error body: %v", err)
	}
	if got.Code != "RATE_LIMITED" {
		t.Fatalf("unexpected error code: %+v", got)
	}
}

// TestFixedWindowLimiter_AllowsBurstThenBlocks exercises the limiter directly,
// including that the window resets over time.
func TestFixedWindowLimiter_AllowsBurstThenBlocks(t *testing.T) {
	l := newFixedWindowLimiter(3, time.Minute)
	now := time.Now()

	for i := 0; i < 3; i++ {
		if !l.allowAt(now) {
			t.Fatalf("attempt %d should be allowed", i+1)
		}
	}
	if l.allowAt(now) {
		t.Fatal("4th attempt within window should be blocked")
	}

	// After the window elapses, attempts are allowed again.
	later := now.Add(time.Minute + time.Second)
	if !l.allowAt(later) {
		t.Fatal("attempt after window should be allowed")
	}
}
