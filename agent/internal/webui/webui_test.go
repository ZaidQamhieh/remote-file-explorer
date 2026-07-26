package webui

import (
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
)

func TestHandlerAddsSecurityHeadersAndScriptNonce(t *testing.T) {
	rr := httptest.NewRecorder()
	Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/", nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d", rr.Code)
	}
	for header, want := range map[string]string{
		"X-Content-Type-Options": "nosniff",
		"X-Frame-Options":        "DENY",
		"Referrer-Policy":        "no-referrer",
	} {
		if got := rr.Header().Get(header); got != want {
			t.Fatalf("%s = %q, want %q", header, got, want)
		}
	}
	csp := rr.Header().Get("Content-Security-Policy")
	match := regexp.MustCompile(`script-src 'nonce-([^']+)'`).FindStringSubmatch(csp)
	if len(match) != 2 {
		t.Fatalf("CSP lacks script nonce: %q", csp)
	}
	if !strings.Contains(rr.Body.String(), `<script nonce="`+match[1]+`">`) {
		t.Fatal("HTML script nonce does not match CSP")
	}
}
