package server

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestDecodeJSONBodyRequiresExactlyOneDocument(t *testing.T) {
	tests := []struct {
		name       string
		body       string
		wantStatus int
		wantOK     bool
	}{
		{name: "single document", body: `{"name":"rfe"}`, wantStatus: http.StatusOK, wantOK: true},
		{name: "second document", body: `{"name":"rfe"} {"name":"other"}`, wantStatus: http.StatusBadRequest},
		{name: "trailing garbage", body: `{"name":"rfe"} trailing`, wantStatus: http.StatusBadRequest},
		{name: "oversized document", body: `{"name":"` + strings.Repeat("a", maxJSONBody) + `"}`, wantStatus: http.StatusRequestEntityTooLarge},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(tc.body))
			rr := httptest.NewRecorder()
			var payload struct {
				Name string `json:"name"`
			}
			if got := decodeJSONBody(rr, req, &payload); got != tc.wantOK {
				t.Fatalf("decodeJSONBody() = %v, want %v", got, tc.wantOK)
			}
			if rr.Code != tc.wantStatus {
				t.Fatalf("status = %d, want %d; body=%s", rr.Code, tc.wantStatus, rr.Body.String())
			}
			if tc.wantOK && payload.Name != "rfe" {
				t.Fatalf("decoded name = %q, want rfe", payload.Name)
			}
		})
	}
}

func TestKeyedLimiterCapsActiveKeysAndSharesOverflowBudget(t *testing.T) {
	limiter := newKeyedLimiter(1, time.Hour)
	limiter.maxKeys = 2

	if !limiter.Allow("source-one") || !limiter.Allow("source-two") {
		t.Fatal("first request from each tracked source should be allowed")
	}
	if !limiter.Allow("overflow-one") {
		t.Fatal("first untracked source should use the overflow budget")
	}
	if limiter.Allow("overflow-two") {
		t.Fatal("untracked sources should share the exhausted overflow budget")
	}
	if got := len(limiter.perKey); got != limiter.maxKeys {
		t.Fatalf("tracked source map grew to %d keys, want cap %d", got, limiter.maxKeys)
	}
}
