package server

import (
	"archive/zip"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
)

func TestArchivePeekHandler_Zip(t *testing.T) {
	dir := t.TempDir()
	zipPath := filepath.Join(dir, "test.zip")

	// Create a zip with 3 files.
	zf, err := os.Create(zipPath)
	if err != nil {
		t.Fatal(err)
	}
	zw := zip.NewWriter(zf)
	for _, name := range []string{"a.txt", "b.txt", "sub/"} {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if name != "sub/" {
			_, _ = w.Write([]byte("content"))
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	zf.Close()

	ops := fsops.New([]string{dir}, false)
	handler := archivePeekHandler(ops)

	req := httptest.NewRequest("GET", "/v1/fs/archive?path="+zipPath, nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200; body: %s", rec.Code, rec.Body.String())
	}

	var resp struct {
		Entries []ArchiveEntry `json:"entries"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatal(err)
	}
	if len(resp.Entries) != 3 {
		t.Fatalf("got %d entries, want 3", len(resp.Entries))
	}
}

func TestArchivePeekHandler_Limit(t *testing.T) {
	dir := t.TempDir()
	zipPath := filepath.Join(dir, "big.zip")

	zf, err := os.Create(zipPath)
	if err != nil {
		t.Fatal(err)
	}
	zw := zip.NewWriter(zf)
	for i := 0; i < 10; i++ {
		w, err := zw.Create("file" + string(rune('a'+i)) + ".txt")
		if err != nil {
			t.Fatal(err)
		}
		_, _ = w.Write([]byte("data"))
	}
	zw.Close()
	zf.Close()

	ops := fsops.New([]string{dir}, false)
	handler := archivePeekHandler(ops)

	req := httptest.NewRequest("GET", "/v1/fs/archive?path="+zipPath+"&limit=3", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}

	var resp struct {
		Entries []ArchiveEntry `json:"entries"`
	}
	json.NewDecoder(rec.Body).Decode(&resp)
	if len(resp.Entries) != 3 {
		t.Fatalf("got %d entries, want 3", len(resp.Entries))
	}
}

func TestArchivePeekHandler_UnsupportedFormat(t *testing.T) {
	dir := t.TempDir()
	f := filepath.Join(dir, "test.rar")
	os.WriteFile(f, []byte("not a rar"), 0o644)

	ops := fsops.New([]string{dir}, false)
	handler := archivePeekHandler(ops)

	req := httptest.NewRequest("GET", "/v1/fs/archive?path="+f, nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want 400", rec.Code)
	}
}

func TestArchivePeekHandler_MissingPath(t *testing.T) {
	dir := t.TempDir()
	ops := fsops.New([]string{dir}, false)
	handler := archivePeekHandler(ops)

	req := httptest.NewRequest("GET", "/v1/fs/archive", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want 400", rec.Code)
	}
}
