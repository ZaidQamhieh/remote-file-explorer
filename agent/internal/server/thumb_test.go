package server

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/thumbs"
)

func TestThumbHandler_ResourceLimitIs413(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "huge.png")
	f, err := os.Create(source)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.Truncate(65 << 20); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	renderer, err := thumbs.New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/thumb?path="+source, nil)
	thumbHandler(fsops.New([]string{root}, false), renderer)(rr, req)

	if rr.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("expected 413, got %d: %s", rr.Code, rr.Body.String())
	}
}
