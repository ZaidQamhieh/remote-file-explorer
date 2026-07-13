package server

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

func TestDeleteTransferHandler(t *testing.T) {
	db, _ := newTestDeps(t)
	tr := &store.Transfer{ID: "t1", TargetPath: "/tmp/foo", TotalSize: 10, ChunkSize: 10, TotalChunks: 1}
	if err := db.CreateTransfer(tr); err != nil {
		t.Fatalf("create transfer: %v", err)
	}

	req := withURLParam(httptest.NewRequest(http.MethodDelete, "/v1/transfers/t1", nil), map[string]string{"id": "t1"})
	rr := httptest.NewRecorder()
	deleteTransferHandler(db)(rr, req)
	if rr.Code != http.StatusNoContent {
		t.Fatalf("want 204, got %d: %s", rr.Code, rr.Body.String())
	}

	req = withURLParam(httptest.NewRequest(http.MethodDelete, "/v1/transfers/t1", nil), map[string]string{"id": "t1"})
	rr = httptest.NewRecorder()
	deleteTransferHandler(db)(rr, req)
	if rr.Code != http.StatusNotFound {
		t.Fatalf("want 404 on second delete, got %d: %s", rr.Code, rr.Body.String())
	}
}
