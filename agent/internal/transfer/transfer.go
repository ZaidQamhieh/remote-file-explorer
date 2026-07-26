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
	"sync"
	"syscall"
	"time"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

// ErrNotFound is returned when the session ID is unknown.
var ErrNotFound = errors.New("transfer not found")

// ErrChunkMismatch is returned when the chunk SHA-256 doesn't match.
var ErrChunkMismatch = errors.New("chunk sha256 mismatch")

// ErrFileMismatch is returned when the whole-file SHA-256 doesn't match.
var ErrFileMismatch = errors.New("whole-file sha256 mismatch")

// ErrInvalidChunk is returned when a chunk index is outside the session or
// its body length does not exactly match that position in the file.
var ErrInvalidChunk = errors.New("invalid chunk")

// ErrIncomplete is returned when completion is requested before every chunk
// has been received.
var ErrIncomplete = errors.New("transfer is incomplete")

// ErrDestinationExists is returned by OpenSession when overwrite=false and
// the target path already exists.
var ErrDestinationExists = errors.New("destination already exists")

// ErrInvalidSession is returned when an upload declaration is malformed.
var ErrInvalidSession = errors.New("invalid transfer session")

// ErrQuotaExceeded is returned when upload size or active-session limits
// would be exceeded.
var ErrQuotaExceeded = errors.New("transfer quota exceeded")

// ErrFileTooLarge identifies the per-file size branch of ErrQuotaExceeded.
var ErrFileTooLarge = errors.New("transfer file too large")

// ErrExpired is returned after an inactive session has been reclaimed.
var ErrExpired = errors.New("transfer session expired")

const (
	MaxChunkSize                    = 32 << 20
	MaxFileSize               int64 = 100 << 30
	maxOpenTransfersGlobal          = 32
	maxOpenTransfersPerDevice       = 8
	maxReservedBytesGlobal          = int64(500 << 30)
	maxReservedBytesPerDevice       = int64(200 << 30)
	transferInactivityTTL           = 24 * time.Hour
	transferSweepInterval           = 15 * time.Minute
)

// Manager coordinates in-progress transfer sessions.
type Manager struct {
	db      *store.DB
	tempDir string // directory for temp files
	openMu  sync.Mutex
	locks   sync.Map
}

// New creates a Manager that stores temp files under tempDir.
func New(db *store.DB, tempDir string) (*Manager, error) {
	if err := os.MkdirAll(tempDir, 0o700); err != nil {
		return nil, fmt.Errorf("create temp dir: %w", err)
	}
	return &Manager{db: db, tempDir: tempDir}, nil
}

// OpenSession creates a new upload session. deviceID is the requesting
// device's ID (empty if unknown, e.g. no device context) — recorded on the
// transfer so the web companion's Transfers page can filter by device.
func (m *Manager) OpenSession(id, targetPath string, size int64, chunkSize int, sha256hex string, overwrite bool, deviceID string) (*store.Transfer, error) {
	if id == "" || id == "." || filepath.Base(id) != id || !filepath.IsAbs(targetPath) || size < 0 || chunkSize <= 0 || chunkSize > MaxChunkSize {
		return nil, ErrInvalidSession
	}
	digest, err := hex.DecodeString(sha256hex)
	if err != nil || len(digest) != sha256.Size {
		return nil, fmt.Errorf("%w: sha256 must be 64 hexadecimal characters", ErrInvalidSession)
	}
	if size > MaxFileSize {
		return nil, fmt.Errorf("%w: %w: file exceeds %d bytes", ErrQuotaExceeded, ErrFileTooLarge, MaxFileSize)
	}

	m.openMu.Lock()
	defer m.openMu.Unlock()
	globalCount, deviceCount, globalBytes, deviceBytes, err := m.db.OpenTransferUsage(deviceID)
	if err != nil {
		return nil, err
	}
	if globalCount >= maxOpenTransfersGlobal || globalBytes > maxReservedBytesGlobal-size {
		return nil, fmt.Errorf("%w: global active-upload limit reached", ErrQuotaExceeded)
	}
	if deviceID != "" && (deviceCount >= maxOpenTransfersPerDevice || deviceBytes > maxReservedBytesPerDevice-size) {
		return nil, fmt.Errorf("%w: device active-upload limit reached", ErrQuotaExceeded)
	}

	if !overwrite {
		if _, err := os.Stat(targetPath); err == nil {
			return nil, ErrDestinationExists
		} else if !os.IsNotExist(err) {
			return nil, err
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
		DeviceID:    deviceID,
		Overwrite:   overwrite,
		CreatedAt:   time.Now().Unix(),
		ExpiresAt:   time.Now().Add(transferInactivityTTL).Unix(),
	}
	if err := m.db.CreateTransfer(t); err != nil {
		os.Remove(tempPath)
		return nil, err
	}
	return t, nil
}

// Status returns the current state of a transfer (for resume).
func (m *Manager) Status(id string) (*store.Transfer, error) {
	lock := m.sessionLock(id)
	lock.Lock()
	defer lock.Unlock()
	t, err := m.db.GetTransfer(id)
	if err != nil {
		return nil, err
	}
	if t == nil {
		return nil, ErrNotFound
	}
	if err := m.expireIfNeeded(t, time.Now()); err != nil {
		return nil, err
	}
	return t, nil
}

// WriteChunk writes chunk n to the temp file after verifying its SHA-256.
// The operation is idempotent: writing the same chunk twice with matching
// hash is a no-op.
func (m *Manager) WriteChunk(id string, n int, chunkData []byte, chunkSHA256 string) error {
	lock := m.sessionLock(id)
	lock.Lock()
	defer lock.Unlock()
	t, err := m.db.GetTransfer(id)
	if err != nil {
		return err
	}
	if t == nil {
		return ErrNotFound
	}
	if err := m.expireIfNeeded(t, time.Now()); err != nil {
		return err
	}
	if t.Status != "open" {
		return fmt.Errorf("transfer is %s, not open", t.Status)
	}
	if n < 0 || n >= t.TotalChunks {
		return fmt.Errorf("%w: index %d outside [0,%d)", ErrInvalidChunk, n, t.TotalChunks)
	}
	expectedSize := t.ChunkSize
	if n == t.TotalChunks-1 {
		expectedSize = int(t.TotalSize - int64(n)*int64(t.ChunkSize))
	}
	if len(chunkData) != expectedSize {
		return fmt.Errorf("%w: chunk %d has %d bytes, want %d", ErrInvalidChunk, n, len(chunkData), expectedSize)
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

	return m.db.MarkChunkReceived(id, n, time.Now().Add(transferInactivityTTL))
}

// Complete verifies the whole-file SHA-256 and atomically renames the temp
// file to the final destination.
func (m *Manager) Complete(id string) (os.FileInfo, string, error) {
	lock := m.sessionLock(id)
	lock.Lock()
	defer lock.Unlock()
	t, err := m.db.GetTransfer(id)
	if err != nil {
		return nil, "", err
	}
	if t == nil {
		return nil, "", ErrNotFound
	}
	if err := m.expireIfNeeded(t, time.Now()); err != nil {
		return nil, "", err
	}
	if t.Status != "open" {
		return nil, "", fmt.Errorf("transfer is %s, not open", t.Status)
	}
	received := make(map[int]struct{}, len(t.ReceivedChunks))
	for _, n := range t.ReceivedChunks {
		received[n] = struct{}{}
	}
	for n := 0; n < t.TotalChunks; n++ {
		if _, ok := received[n]; !ok {
			return nil, "", fmt.Errorf("%w: missing chunk %d", ErrIncomplete, n)
		}
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
		// The temp file is now orphaned (the transfer can't be resumed once
		// failed) — remove it so it doesn't leak on disk.
		_ = os.Remove(t.TempPath)
		return nil, "", fmt.Errorf("%w: got %s want %s", ErrFileMismatch, got, t.SHA256)
	}

	// Ensure parent directory exists.
	if err := os.MkdirAll(filepath.Dir(t.TargetPath), 0o755); err != nil {
		return nil, "", err
	}

	// Move temp → final. os.Rename is atomic when both are on the same
	// filesystem; when the destination is on a different mount (e.g. an
	// external backup drive) it fails with EXDEV, so fall back to a
	// copy-into-dest-dir + atomic-rename-within-dest. Without this every
	// cross-filesystem transfer's Complete failed here, leaving the row
	// stuck "open" forever (see the photo-backup leak).
	if err := m.db.SetTransferStatus(id, "publishing"); err != nil {
		return nil, "", fmt.Errorf("record publishing state: %w", err)
	}
	if err := publishFile(t.TempPath, t.TargetPath, t.Overwrite); err != nil {
		_ = m.db.SetTransferStatus(id, "open")
		return nil, "", fmt.Errorf("rename: %w", err)
	}

	if err := m.db.SetTransferStatus(id, "completed"); err != nil {
		return nil, t.TargetPath, fmt.Errorf("record completed state: %w", err)
	}

	info, err := os.Stat(t.TargetPath)
	if err != nil {
		return nil, t.TargetPath, nil
	}
	return info, t.TargetPath, nil
}

func (m *Manager) sessionLock(id string) *sync.Mutex {
	lock, _ := m.locks.LoadOrStore(id, &sync.Mutex{})
	return lock.(*sync.Mutex)
}

func (m *Manager) expireIfNeeded(t *store.Transfer, now time.Time) error {
	if t.Status != "open" || t.ExpiresAt == 0 || t.ExpiresAt > now.Unix() {
		return nil
	}
	claimed, err := m.db.ExpireTransfer(t.ID, now.Unix())
	if err != nil {
		return err
	}
	if claimed {
		_ = os.Remove(t.TempPath)
		_ = m.db.DeleteTransfer(t.ID)
	}
	return ErrExpired
}

// SweepExpired reclaims abandoned sessions and their temporary files.
func (m *Manager) SweepExpired(now time.Time) (int, error) {
	transfers, err := m.db.ExpiredOpenTransfers(now.Unix())
	if err != nil {
		return 0, err
	}
	removed := 0
	for i := range transfers {
		t := &transfers[i]
		lock := m.sessionLock(t.ID)
		lock.Lock()
		claimed, claimErr := m.db.ExpireTransfer(t.ID, now.Unix())
		if claimErr != nil {
			lock.Unlock()
			return removed, claimErr
		}
		if !claimed {
			lock.Unlock()
			continue
		}
		if removeErr := os.Remove(t.TempPath); removeErr != nil && !os.IsNotExist(removeErr) {
			_ = m.db.SetTransferStatus(t.ID, "open")
			lock.Unlock()
			return removed, removeErr
		}
		if deleteErr := m.db.DeleteTransfer(t.ID); deleteErr != nil {
			lock.Unlock()
			return removed, deleteErr
		}
		lock.Unlock()
		m.locks.Delete(t.ID)
		removed++
	}
	return removed, nil
}

// StartSweeper periodically reclaims abandoned upload sessions for the life
// of the agent process.
func (m *Manager) StartSweeper() {
	go func() {
		ticker := time.NewTicker(transferSweepInterval)
		defer ticker.Stop()
		for now := range ticker.C {
			_, _ = m.SweepExpired(now)
		}
	}()
}

func publishFile(src, dst string, overwrite bool) error {
	if overwrite {
		return moveFile(src, dst)
	}
	if err := os.Link(src, dst); err == nil {
		return os.Remove(src)
	} else if errors.Is(err, os.ErrExist) {
		return ErrDestinationExists
	} else if errors.Is(err, syscall.EXDEV) {
		return copyAcrossNoReplace(src, dst)
	} else {
		return err
	}
}

// moveFile moves src to dst atomically when possible. It tries os.Rename first
// (atomic, same-filesystem); on a cross-device error (EXDEV — dst is on a
// different mount than src) it copies src into dst's directory and atomically
// renames within that directory, then removes src.
func moveFile(src, dst string) error {
	if err := os.Rename(src, dst); err == nil {
		return nil
	} else if !errors.Is(err, syscall.EXDEV) {
		return err
	}
	return copyAcross(src, dst)
}

// copyAcross copies src to a temp file in dst's own directory, fsyncs it, then
// atomically renames it onto dst (both now on the same filesystem) and removes
// src. A failure at any step leaves dst untouched and cleans up the temp.
func copyAcross(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	tmp, err := os.CreateTemp(filepath.Dir(dst), ".rfe-move-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	cleanup := func() { tmp.Close(); os.Remove(tmpName) }

	if _, err := io.Copy(tmp, in); err != nil {
		cleanup()
		return err
	}
	if err := tmp.Sync(); err != nil {
		cleanup()
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpName)
		return err
	}
	if err := os.Rename(tmpName, dst); err != nil {
		os.Remove(tmpName)
		return err
	}
	return os.Remove(src)
}

func copyAcrossNoReplace(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	tmp, err := os.CreateTemp(filepath.Dir(dst), ".rfe-move-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	cleanup := func() { tmp.Close(); os.Remove(tmpName) }
	if _, err := io.Copy(tmp, in); err != nil {
		cleanup()
		return err
	}
	if err := tmp.Sync(); err != nil {
		cleanup()
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpName)
		return err
	}
	if err := os.Link(tmpName, dst); err != nil {
		os.Remove(tmpName)
		if errors.Is(err, os.ErrExist) {
			return ErrDestinationExists
		}
		return err
	}
	if err := os.Remove(tmpName); err != nil {
		return err
	}
	return os.Remove(src)
}
