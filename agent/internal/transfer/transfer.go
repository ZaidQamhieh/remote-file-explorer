// Package transfer handles resumable file uploads.
//
// Flow:
//  1. POST /v1/transfers           → OpenSession → returns UploadSession
//  2. PUT  /v1/transfers/{id}/chunks/{n} → WriteChunk (idempotent, hash-verified)
//  3. GET  /v1/transfers/{id}       → Status (for resume)
//  4. POST /v1/transfers/{id}/complete → Complete (verify whole-file SHA-256, atomic rename)
package transfer

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

// ErrNotFound is returned when the session ID is unknown.
var ErrNotFound = errors.New("transfer not found")

// ErrChunkMismatch is returned when the chunk SHA-256 doesn't match.
var ErrChunkMismatch = errors.New("chunk sha256 mismatch")

// ErrFileMismatch is returned when the whole-file SHA-256 doesn't match.
var ErrFileMismatch = errors.New("whole-file sha256 mismatch")

// Manager coordinates in-progress transfer sessions.
type Manager struct {
	db      *store.DB
	tempDir string // directory for temp files
}

// New creates a Manager that stores temp files under tempDir.
func New(db *store.DB, tempDir string) (*Manager, error) {
	if err := os.MkdirAll(tempDir, 0o700); err != nil {
		return nil, fmt.Errorf("create temp dir: %w", err)
	}
	return &Manager{db: db, tempDir: tempDir}, nil
}

// OpenSession creates a new upload session.
func (m *Manager) OpenSession(id, targetPath string, size int64, chunkSize int, sha256hex string, overwrite bool) (*store.Transfer, error) {
	if !overwrite {
		if _, err := os.Stat(targetPath); err == nil {
			return nil, fmt.Errorf("destination already exists (overwrite=false)")
		}
	}
	totalChunks := int((size + int64(chunkSize) - 1) / int64(chunkSize))
	if totalChunks == 0 {
		totalChunks = 1
	}
	tempPath := filepath.Join(m.tempDir, id+".tmp")

	// Pre-allocate the file.
	f, err := os.OpenFile(tempPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return nil, fmt.Errorf("create temp file: %w", err)
	}
	if size > 0 {
		if err := f.Truncate(size); err != nil {
			f.Close()
			return nil, fmt.Errorf("truncate: %w", err)
		}
	}
	f.Close()

	t := &store.Transfer{
		ID:          id,
		TargetPath:  targetPath,
		TotalSize:   size,
		ChunkSize:   chunkSize,
		SHA256:      sha256hex,
		TotalChunks: totalChunks,
		TempPath:    tempPath,
		Status:      "open",
	}
	if err := m.db.CreateTransfer(t); err != nil {
		os.Remove(tempPath)
		return nil, err
	}
	return t, nil
}

// Status returns the current state of a transfer (for resume).
func (m *Manager) Status(id string) (*store.Transfer, error) {
	t, err := m.db.GetTransfer(id)
	if err != nil {
		return nil, err
	}
	if t == nil {
		return nil, ErrNotFound
	}
	return t, nil
}

// WriteChunk writes chunk n to the temp file after verifying its SHA-256.
// The operation is idempotent: writing the same chunk twice with matching
// hash is a no-op.
func (m *Manager) WriteChunk(id string, n int, chunkData []byte, chunkSHA256 string) error {
	t, err := m.db.GetTransfer(id)
	if err != nil {
		return err
	}
	if t == nil {
		return ErrNotFound
	}
	if t.Status != "open" {
		return fmt.Errorf("transfer is %s, not open", t.Status)
	}

	// Verify chunk hash.
	sum := sha256.Sum256(chunkData)
	got := hex.EncodeToString(sum[:])
	if got != chunkSHA256 {
		return fmt.Errorf("%w: got %s want %s", ErrChunkMismatch, got, chunkSHA256)
	}

	// Check idempotency: if already received skip writing but return success.
	for _, received := range t.ReceivedChunks {
		if received == n {
			return nil
		}
	}

	offset := int64(n) * int64(t.ChunkSize)
	f, err := os.OpenFile(t.TempPath, os.O_WRONLY, 0o600)
	if err != nil {
		return fmt.Errorf("open temp file: %w", err)
	}
	defer f.Close()
	if _, err := f.WriteAt(chunkData, offset); err != nil {
		return fmt.Errorf("write chunk: %w", err)
	}

	return m.db.MarkChunkReceived(id, n)
}

// Complete verifies the whole-file SHA-256 and atomically renames the temp
// file to the final destination.
func (m *Manager) Complete(id string) (*os.FileInfo, string, error) {
	t, err := m.db.GetTransfer(id)
	if err != nil {
		return nil, "", err
	}
	if t == nil {
		return nil, "", ErrNotFound
	}
	if t.Status != "open" {
		return nil, "", fmt.Errorf("transfer is %s, not open", t.Status)
	}

	// Verify whole-file hash.
	f, err := os.Open(t.TempPath)
	if err != nil {
		return nil, "", fmt.Errorf("open temp: %w", err)
	}
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		f.Close()
		return nil, "", fmt.Errorf("hash file: %w", err)
	}
	f.Close()

	got := hex.EncodeToString(h.Sum(nil))
	if got != t.SHA256 {
		_ = m.db.SetTransferStatus(id, "failed")
		return nil, "", fmt.Errorf("%w: got %s want %s", ErrFileMismatch, got, t.SHA256)
	}

	// Ensure parent directory exists.
	if err := os.MkdirAll(filepath.Dir(t.TargetPath), 0o755); err != nil {
		return nil, "", err
	}

	// Atomic rename.
	if err := os.Rename(t.TempPath, t.TargetPath); err != nil {
		return nil, "", fmt.Errorf("rename: %w", err)
	}

	_ = m.db.SetTransferStatus(id, "completed")

	info, err := os.Stat(t.TargetPath)
	if err != nil {
		return nil, t.TargetPath, nil
	}
	return &info, t.TargetPath, nil
}
