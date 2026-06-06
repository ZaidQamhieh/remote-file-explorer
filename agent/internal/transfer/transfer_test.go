package transfer

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"

	"github.com/google/uuid"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

func setupManager(t *testing.T) (*Manager, *store.DB, string) {
	t.Helper()
	dataDir := t.TempDir()
	db, err := store.Open(dataDir)
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	t.Cleanup(func() { db.Close() })

	tempDir := filepath.Join(dataDir, "tmp")
	tm, err := New(db, tempDir)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	return tm, db, dataDir
}

// TestOpenSession verifies a session is created and retrievable.
func TestOpenSession(t *testing.T) {
	tm, _, dataDir := setupManager(t)
	target := filepath.Join(dataDir, "out", "file.bin")
	id := uuid.New().String()
	content := []byte("hello world")
	hash := sha256hex(content)

	sess, err := tm.OpenSession(id, target, int64(len(content)), 64, hash, false)
	if err != nil {
		t.Fatalf("OpenSession: %v", err)
	}
	if sess.Status != "open" {
		t.Fatalf("expected open, got %s", sess.Status)
	}
	if sess.TotalChunks != 1 {
		t.Fatalf("expected 1 chunk, got %d", sess.TotalChunks)
	}

	// Retrieve.
	got, err := tm.Status(id)
	if err != nil {
		t.Fatalf("Status: %v", err)
	}
	if got.ID != id {
		t.Fatalf("id mismatch")
	}
}

// TestSingleChunkUploadComplete tests the happy path for a small single-chunk file.
func TestSingleChunkUploadComplete(t *testing.T) {
	tm, _, dataDir := setupManager(t)
	target := filepath.Join(dataDir, "out.bin")
	content := []byte("the quick brown fox")
	hash := sha256hex(content)
	id := uuid.New().String()

	_, err := tm.OpenSession(id, target, int64(len(content)), 1024, hash, false)
	if err != nil {
		t.Fatalf("OpenSession: %v", err)
	}

	chunkHash := sha256hex(content)
	if err := tm.WriteChunk(id, 0, content, chunkHash); err != nil {
		t.Fatalf("WriteChunk: %v", err)
	}

	// Status should show chunk 0 received.
	sess, err := tm.Status(id)
	if err != nil {
		t.Fatalf("Status: %v", err)
	}
	if len(sess.ReceivedChunks) != 1 || sess.ReceivedChunks[0] != 0 {
		t.Fatalf("expected [0], got %v", sess.ReceivedChunks)
	}

	// Complete.
	_, finalPath, err := tm.Complete(id)
	if err != nil {
		t.Fatalf("Complete: %v", err)
	}
	if _, err := os.Stat(finalPath); err != nil {
		t.Fatalf("final file missing: %v", err)
	}
	// Verify content.
	data, err := os.ReadFile(finalPath)
	if err != nil {
		t.Fatalf("read final: %v", err)
	}
	if string(data) != string(content) {
		t.Fatalf("content mismatch: got %q want %q", data, content)
	}
}

// TestMultiChunkResume tests the multi-chunk resume scenario:
// open session, upload some chunks, query missing chunks, upload remaining, complete.
func TestMultiChunkResume(t *testing.T) {
	tm, _, dataDir := setupManager(t)
	target := filepath.Join(dataDir, "multi.bin")

	// Build a 30-byte payload in 3 chunks of 10.
	chunk0 := []byte("0123456789")
	chunk1 := []byte("abcdefghij")
	chunk2 := []byte("ABCDEFGHIJ")
	content := append(append(chunk0, chunk1...), chunk2...)
	fileHash := sha256hex(content)
	id := uuid.New().String()

	_, err := tm.OpenSession(id, target, 30, 10, fileHash, false)
	if err != nil {
		t.Fatalf("OpenSession: %v", err)
	}

	// Upload chunks 0 and 2 (skip 1 to simulate partial upload).
	if err := tm.WriteChunk(id, 0, chunk0, sha256hex(chunk0)); err != nil {
		t.Fatalf("WriteChunk 0: %v", err)
	}
	if err := tm.WriteChunk(id, 2, chunk2, sha256hex(chunk2)); err != nil {
		t.Fatalf("WriteChunk 2: %v", err)
	}

	// Status should report chunks 0 and 2 received.
	sess, err := tm.Status(id)
	if err != nil {
		t.Fatalf("Status: %v", err)
	}
	if len(sess.ReceivedChunks) != 2 {
		t.Fatalf("expected 2 received, got %v", sess.ReceivedChunks)
	}

	// Derive missing chunks.
	receivedSet := map[int]bool{}
	for _, c := range sess.ReceivedChunks {
		receivedSet[c] = true
	}
	for i := 0; i < sess.TotalChunks; i++ {
		if !receivedSet[i] {
			// Missing chunk — upload it.
			if err := tm.WriteChunk(id, i, chunk1, sha256hex(chunk1)); err != nil {
				t.Fatalf("WriteChunk missing %d: %v", i, err)
			}
		}
	}

	// Idempotency: re-upload chunk 0 — should succeed.
	if err := tm.WriteChunk(id, 0, chunk0, sha256hex(chunk0)); err != nil {
		t.Fatalf("idempotent WriteChunk 0: %v", err)
	}

	// Complete.
	_, finalPath, err := tm.Complete(id)
	if err != nil {
		t.Fatalf("Complete: %v", err)
	}
	data, _ := os.ReadFile(finalPath)
	if string(data) != string(content) {
		t.Fatalf("content mismatch")
	}
}

// TestHashMismatch verifies Complete rejects a file whose hash doesn't match.
func TestHashMismatch(t *testing.T) {
	tm, _, dataDir := setupManager(t)
	target := filepath.Join(dataDir, "bad.bin")
	content := []byte("real content")
	wrongHash := sha256hex([]byte("wrong content"))
	id := uuid.New().String()

	_, err := tm.OpenSession(id, target, int64(len(content)), 1024, wrongHash, false)
	if err != nil {
		t.Fatalf("OpenSession: %v", err)
	}
	if err := tm.WriteChunk(id, 0, content, sha256hex(content)); err != nil {
		t.Fatalf("WriteChunk: %v", err)
	}
	_, _, err = tm.Complete(id)
	if err == nil {
		t.Fatal("expected hash mismatch error")
	}
}

// TestChunkHashMismatch verifies WriteChunk rejects bad chunk data.
func TestChunkHashMismatch(t *testing.T) {
	tm, _, dataDir := setupManager(t)
	target := filepath.Join(dataDir, "chunkerr.bin")
	content := []byte("some data")
	id := uuid.New().String()

	_, err := tm.OpenSession(id, target, int64(len(content)), 1024, sha256hex(content), false)
	if err != nil {
		t.Fatalf("OpenSession: %v", err)
	}
	err = tm.WriteChunk(id, 0, content, "0000000000000000000000000000000000000000000000000000000000000000")
	if err == nil {
		t.Fatal("expected chunk hash mismatch error")
	}
}

func sha256hex(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}
