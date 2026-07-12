package server

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/transfer"
)

// newTestTransferManager builds a transfer.Manager backed by a fresh DB and
// temp dir, plus an Ops with no path jail.
func newTestTransferManager(t *testing.T) (*transfer.Manager, *fsops.Ops) {
	t.Helper()
	db, st := newTestDeps(t)
	tm, err := transfer.New(db, t.TempDir())
	if err != nil {
		t.Fatalf("transfer.New: %v", err)
	}
	ops := fsops.NewWithSettings(st)
	return tm, ops
}

// withURLParam returns req with chi URL params set, so chi.URLParam works
// when invoking handlers directly (without the router).
func withURLParam(req *http.Request, params map[string]string) *http.Request {
	rctx := chi.NewRouteContext()
	for k, v := range params {
		rctx.URLParams.Add(k, v)
	}
	return req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))
}

func sha256hex(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

// TestOpenTransferHandler_ChunkSizeOverCapIs400 verifies the open-session
// handler rejects a chunkSize above the 32MiB cap with a 400.
func TestOpenTransferHandler_ChunkSizeOverCapIs400(t *testing.T) {
	tm, ops := newTestTransferManager(t)

	body := `{"path":"file.bin","size":100,"sha256":"deadbeef","chunkSize":33554433}`
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/transfers", strings.NewReader(body))
	openTransferHandler(tm, ops)(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rr.Code, rr.Body.String())
	}
	var got apiError
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode error body: %v", err)
	}
	if got.Code != "BAD_REQUEST" {
		t.Fatalf("unexpected error code: %+v", got)
	}
}

// TestOpenTransferHandler_NegativeSizeIs400 verifies the open-session handler
// rejects a negative size with a 400 BAD_REQUEST. A negative size would break
// the totalChunks calculation and os.Truncate downstream.
func TestOpenTransferHandler_NegativeSizeIs400(t *testing.T) {
	tm, ops := newTestTransferManager(t)

	body := `{"path":"file.bin","size":-1,"sha256":"deadbeef","chunkSize":1024}`
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/transfers", strings.NewReader(body))
	openTransferHandler(tm, ops)(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rr.Code, rr.Body.String())
	}
	var got apiError
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode error body: %v", err)
	}
	if got.Code != "BAD_REQUEST" {
		t.Fatalf("unexpected error code: %+v", got)
	}
}

// TestOpenTransferHandler_ZeroSizeIsAllowed sanity-checks that a zero-byte
// file (a legitimate upload) is accepted.
func TestOpenTransferHandler_ZeroSizeIsAllowed(t *testing.T) {
	tm, ops := newTestTransferManager(t)

	target := filepath.Join(t.TempDir(), "empty.bin")
	body := `{"path":"` + target + `","size":0,"sha256":"` + sha256hex(nil) + `","chunkSize":1024}`
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/transfers", strings.NewReader(body))
	openTransferHandler(tm, ops)(rr, req)

	if rr.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rr.Code, rr.Body.String())
	}
}

// TestOpenTransferHandler_DestinationExistsIs409 verifies that opening an
// upload session for a target path that already exists, without overwrite,
// returns 409 CONFLICT rather than 500 INTERNAL.
func TestOpenTransferHandler_DestinationExistsIs409(t *testing.T) {
	tm, ops := newTestTransferManager(t)

	target := filepath.Join(t.TempDir(), "existing.bin")
	if err := os.WriteFile(target, []byte("already here"), 0o644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	body := `{"path":"` + target + `","size":11,"sha256":"` + sha256hex([]byte("hello world")) + `","chunkSize":1024}`
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/transfers", strings.NewReader(body))
	openTransferHandler(tm, ops)(rr, req)

	if rr.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d: %s", rr.Code, rr.Body.String())
	}
	var got apiError
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode error body: %v", err)
	}
	if got.Code != "CONFLICT" {
		t.Fatalf("unexpected error code: %+v", got)
	}
}

// TestOpenTransferHandler_OverwriteBypassesConflict verifies that
// overwrite=true allows opening a session for a target path that already
// exists.
func TestOpenTransferHandler_OverwriteBypassesConflict(t *testing.T) {
	tm, ops := newTestTransferManager(t)

	target := filepath.Join(t.TempDir(), "existing.bin")
	if err := os.WriteFile(target, []byte("already here"), 0o644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	body := `{"path":"` + target + `","size":11,"sha256":"` + sha256hex([]byte("hello world")) + `","chunkSize":1024,"overwrite":true}`
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/transfers", strings.NewReader(body))
	openTransferHandler(tm, ops)(rr, req)

	if rr.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rr.Code, rr.Body.String())
	}
}

// TestOpenTransferHandler_ChunkSizeAtCapIsAllowed sanity-checks the boundary:
// exactly 32MiB is accepted.
func TestOpenTransferHandler_ChunkSizeAtCapIsAllowed(t *testing.T) {
	tm, ops := newTestTransferManager(t)

	target := filepath.Join(t.TempDir(), "file.bin")
	body := `{"path":"` + target + `","size":100,"sha256":"deadbeef","chunkSize":33554432}`
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/transfers", strings.NewReader(body))
	openTransferHandler(tm, ops)(rr, req)

	if rr.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rr.Code, rr.Body.String())
	}
}

// TestUploadChunkHandler_OversizedBodyIs413 verifies a chunk body larger than
// the session's chunkSize is rejected with 413, using the error envelope.
func TestUploadChunkHandler_OversizedBodyIs413(t *testing.T) {
	tm, ops := newTestTransferManager(t)

	target := filepath.Join(t.TempDir(), "out.bin")
	const chunkSize = 16
	content := make([]byte, chunkSize*2)
	id := uuid.New().String()
	sess, err := tm.OpenSession(id, target, int64(len(content)), chunkSize, sha256hex(content), false, "")
	if err != nil {
		t.Fatalf("OpenSession: %v", err)
	}
	_ = ops // ops unused beyond constructing tm in this subtest

	// Body larger than chunkSize.
	oversized := make([]byte, chunkSize+1)
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPut, "/v1/transfers/"+id+"/chunks/0", strings.NewReader(string(oversized)))
	req.Header.Set("X-Chunk-Sha256", sha256hex(oversized))
	req = withURLParam(req, map[string]string{"id": id, "n": "0"})

	uploadChunkHandler(tm)(rr, req)

	if rr.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("expected 413, got %d: %s", rr.Code, rr.Body.String())
	}
	var got apiError
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode error body: %v", err)
	}
	if got.Code != "PAYLOAD_TOO_LARGE" {
		t.Fatalf("unexpected error code: %+v", got)
	}

	// Sanity: the session is unaffected (still open, no chunk recorded).
	got2, err := tm.Status(sess.ID)
	if err != nil {
		t.Fatalf("Status: %v", err)
	}
	if len(got2.ReceivedChunks) != 0 {
		t.Fatalf("expected no chunks recorded, got %v", got2.ReceivedChunks)
	}
}

// TestCompleteTransferHandler_SuccessIncludesVerifiedSHA256 verifies that a
// successful POST /transfers/{id}/complete response includes verified=true
// and the expected whole-file sha256 (H3 — post-transfer integrity check).
func TestCompleteTransferHandler_SuccessIncludesVerifiedSHA256(t *testing.T) {
	tm, ops := newTestTransferManager(t)

	content := []byte("hello world, this is the uploaded file content")
	wantSHA256 := sha256hex(content)
	target := filepath.Join(t.TempDir(), "out.bin")

	id := uuid.New().String()
	if _, err := tm.OpenSession(id, target, int64(len(content)), 1024, wantSHA256, false, ""); err != nil {
		t.Fatalf("OpenSession: %v", err)
	}

	// Write the single chunk.
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPut, "/v1/transfers/"+id+"/chunks/0", strings.NewReader(string(content)))
	req.Header.Set("X-Chunk-Sha256", sha256hex(content))
	req = withURLParam(req, map[string]string{"id": id, "n": "0"})
	uploadChunkHandler(tm)(rr, req)
	if rr.Code != http.StatusNoContent {
		t.Fatalf("upload chunk: expected 204, got %d: %s", rr.Code, rr.Body.String())
	}

	// Complete the transfer.
	rr = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodPost, "/v1/transfers/"+id+"/complete", nil)
	req = withURLParam(req, map[string]string{"id": id})
	completeTransferHandler(tm, ops)(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}

	var got map[string]any
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode response: %v", err)
	}

	verified, ok := got["verified"].(bool)
	if !ok || !verified {
		t.Fatalf("expected verified=true, got %+v", got["verified"])
	}
	if got["sha256"] != wantSHA256 {
		t.Fatalf("expected sha256=%s, got %v", wantSHA256, got["sha256"])
	}
	// Sanity: the usual Entry fields are still present.
	if got["path"] == nil || got["size"] == nil {
		t.Fatalf("expected Entry fields in response, got %+v", got)
	}
}

// TestUploadChunkHandler_ExactSizeIsAccepted sanity-checks that a body
// exactly matching chunkSize still succeeds.
func TestUploadChunkHandler_ExactSizeIsAccepted(t *testing.T) {
	tm, _ := newTestTransferManager(t)

	target := filepath.Join(t.TempDir(), "out.bin")
	const chunkSize = 16
	content := make([]byte, chunkSize)
	for i := range content {
		content[i] = byte(i)
	}
	id := uuid.New().String()
	if _, err := tm.OpenSession(id, target, int64(len(content)), chunkSize, sha256hex(content), false, ""); err != nil {
		t.Fatalf("OpenSession: %v", err)
	}

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPut, "/v1/transfers/"+id+"/chunks/0", strings.NewReader(string(content)))
	req.Header.Set("X-Chunk-Sha256", sha256hex(content))
	req = withURLParam(req, map[string]string{"id": id, "n": "0"})

	uploadChunkHandler(tm)(rr, req)

	if rr.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d: %s", rr.Code, rr.Body.String())
	}
}
