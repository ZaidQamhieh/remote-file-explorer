//go:build linux

// Audit 2026-10-20 reproductions. Each test demonstrates a verified defect and
// FAILS while the defect exists, so the suite skips them unless
// RFE_AUDIT_REPRO=1. See docs/audit/2026-10-20-audit.md.
package server

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
)

func auditRepro(t *testing.T) {
	t.Helper()
	if os.Getenv("RFE_AUDIT_REPRO") != "1" {
		t.Skip("audit repro; set RFE_AUDIT_REPRO=1")
	}
}

// F-03: downloading a FIFO inside the root blocks the request forever instead of
// being refused.
func TestAuditRepro_DownloadFIFOReturnsPromptly(t *testing.T) {
	auditRepro(t)
	root := t.TempDir()
	fifo := filepath.Join(root, "pipe")
	if err := syscall.Mkfifo(fifo, 0o644); err != nil {
		t.Fatal(err)
	}
	ops := fsops.New([]string{root}, false)
	done := make(chan *httptest.ResponseRecorder, 1)
	go func() { done <- getContent(ops, fifo, nil) }()
	select {
	case rr := <-done:
		if rr.Code == http.StatusOK {
			t.Fatalf("FIFO served with 200")
		}
	case <-time.After(3 * time.Second):
		t.Fatal("download of a FIFO is blocked after 3s (request and goroutine leak)")
	}
}

// F-05: expiresInSeconds is multiplied by time.Second before the 24h cap
// comparison; 18446744074 s overflows int64 to ~0.29 s and passes the check.
func TestAuditRepro_ShareExpiryOverflowRejected(t *testing.T) {
	auditRepro(t)
	ops, root := newFsFixture(t)
	db, st := newTestDeps(t)
	if err := st.SetAllowSharing(true); err != nil {
		t.Fatal(err)
	}
	handler := mintShareHandler(Config{Address: "127.0.0.1:8765", Settings: st}, db, ops)
	body := `{"path":"` + filepath.Join(root, "a.txt") + `","expiresInSeconds":18446744074}`
	rr := httptest.NewRecorder()
	handler(rr, httptest.NewRequest(http.MethodPost, "/v1/share/mint", strings.NewReader(body)))
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expiresInSeconds above the 24h cap accepted: %d %s", rr.Code, rr.Body.String())
	}
}
