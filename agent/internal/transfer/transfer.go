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
	"io/fs"
	"os"
	"path/filepath"
	"syscall"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

// ErrNotFound is returned when the session ID is unknown.
var ErrNotFound = errors.New("transfer not found")

// ErrChunkMismatch is returned when the chunk SHA-256 doesn't match.
var ErrChunkMismatch = errors.New("chunk sha256 mismatch")

// ErrFileMismatch is returned when the whole-file SHA-256 doesn't match.
var ErrFileMismatch = errors.New("whole-file sha256 mismatch")

// ErrDestinationExists is returned by OpenSession when overwrite=false and
// the target path already exists.
var ErrDestinationExists = errors.New("destination already exists")

// ErrChunkOutOfRange is returned when a chunk index falls outside the
// session's declared chunk count.
var ErrChunkOutOfRange = errors.New("chunk index out of range")

// ErrChunkWrongSize is returned when a chunk's length is not exactly the
// length the session's geometry requires.
var ErrChunkWrongSize = errors.New("chunk has the wrong length")

// ErrTooLarge is returned when a session declares more bytes than
// maxTransferSize, or than the destination filesystem can hold.
var ErrTooLarge = errors.New("declared size exceeds the maximum")

// maxTransferSize caps a single declared upload. OpenSession truncates the
// temp file to the declared size up front, so an unbounded declaration is a
// free sparse file of any size a client cares to name — and on filesystems
// without sparse support, an instant disk fill (PR-12).
//
// ponytail: one global ceiling, not a per-device quota — add the quota when
// there is more than one writer worth metering.
const maxTransferSize = int64(1) << 40 // 1 TiB

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

// OpenSession creates a new upload session. deviceID is the requesting
// device's ID (empty if unknown, e.g. no device context) — recorded on the
// transfer so the web companion's Transfers page can filter by device.
//
// The overwrite=false check here is a courtesy: it fails the client early
// instead of after a long upload. It is not the guarantee — Complete re-checks
// atomically at publish time, because anything created during the upload would
// slip past this Stat (PR-50).
func (m *Manager) OpenSession(id, targetPath string, size int64, chunkSize int, sha256hex string, overwrite bool, deviceID string) (*store.Transfer, error) {
	if size < 0 {
		return nil, fmt.Errorf("%w: negative size", ErrTooLarge)
	}
	if size > maxTransferSize {
		return nil, fmt.Errorf("%w: %d bytes declared, limit %d", ErrTooLarge, size, maxTransferSize)
	}
	if !overwrite {
		if _, err := os.Stat(targetPath); err == nil {
			return nil, ErrDestinationExists
		}
	}
	// ponytail: a flat ceiling, not a free-space check — free space lives
	// behind three per-platform files in fsops and would need a new exported
	// helper in each. The cap is what stops the abuse; add the reservation
	// check if real disks start filling below 1 TiB.
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
	}
	if err := m.db.CreateTransfer(t); err != nil {
		os.Remove(tempPath)
		return nil, err
	}
	return t, nil
}

// Status returns the current state of a transfer (for resume). This is the
// one path that genuinely needs every received chunk number — the client diffs
// the set to decide what to re-send — so it loads them explicitly; GetTransfer
// no longer carries them (PR-42).
func (m *Manager) Status(id string) (*store.Transfer, error) {
	t, err := m.db.GetTransfer(id)
	if err != nil {
		return nil, err
	}
	if t == nil {
		return nil, ErrNotFound
	}
	chunks, err := m.db.ChunkNumbers(id)
	if err != nil {
		return nil, err
	}
	t.ReceivedChunks = chunks
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

	// The chunk index drives a WriteAt offset (n * chunkSize). Unchecked, a
	// large n seeks far past the declared size and leaves a sparse file of the
	// client's choosing; a negative one is a negative offset (PR-12).
	if n < 0 || n >= t.TotalChunks {
		return fmt.Errorf("%w: chunk %d of %d", ErrChunkOutOfRange, n, t.TotalChunks)
	}
	// Every chunk but the last must be exactly chunkSize, and the last exactly
	// the remainder. The body cap alone only bounds the maximum, so a short
	// chunk would silently leave a hole of zeros inside the file.
	if want := t.ExpectedChunkLen(n); len(chunkData) != want {
		return fmt.Errorf("%w: chunk %d is %d bytes, want %d", ErrChunkWrongSize, n, len(chunkData), want)
	}

	// Verify chunk hash.
	sum := sha256.Sum256(chunkData)
	got := hex.EncodeToString(sum[:])
	if got != chunkSHA256 {
		return fmt.Errorf("%w: got %s want %s", ErrChunkMismatch, got, chunkSHA256)
	}

	// Check idempotency: if already received skip writing but return success.
	// An indexed lookup, not a scan of every chunk received so far — the
	// latter made a large transfer quadratic all on its own (PR-42).
	switch has, err := m.db.HasChunk(id, n); {
	case err != nil:
		return err
	case has:
		return nil
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
func (m *Manager) Complete(id string) (os.FileInfo, string, error) {
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
	//
	// overwrite=false is checked again here, atomically: OpenSession's Stat
	// happens before the upload, so a file created during it would otherwise
	// be silently replaced at this rename (PR-50).
	if err := publish(t.TempPath, t.TargetPath, t.Overwrite); err != nil {
		if errors.Is(err, ErrDestinationExists) {
			return nil, "", err
		}
		return nil, "", fmt.Errorf("rename: %w", err)
	}

	// The bytes are on disk under the final name — the transfer succeeded even
	// if recording that fails, so surface the persistence error instead of
	// dropping it and leaving the row stuck "open" (PR-50).
	if err := m.db.SetTransferStatus(id, "completed"); err != nil {
		return nil, t.TargetPath, fmt.Errorf("transfer published to %s but recording it failed: %w", t.TargetPath, err)
	}

	info, err := os.Stat(t.TargetPath)
	if err != nil {
		return nil, t.TargetPath, nil
	}
	return info, t.TargetPath, nil
}

// publish moves the finished temp file onto its final path. With overwrite it
// replaces whatever is there (moveFile); without it, the create must fail
// rather than replace a file that appeared during the upload — OpenSession's
// Stat is far too early to rely on (PR-50).
//
// The no-replace path uses os.Link, which fails with EEXIST if dst exists and
// so decides atomically, unlike a Stat-then-rename. Link needs both paths on
// one filesystem and a backing FS that supports it; any other failure falls
// back to an O_EXCL copy, which is equally atomic about not clobbering.
func publish(src, dst string, overwrite bool) error {
	if overwrite {
		return moveFile(src, dst)
	}
	switch err := os.Link(src, dst); {
	case err == nil:
		return os.Remove(src) // dst is now a second name for the same inode
	case errors.Is(err, fs.ErrExist):
		return ErrDestinationExists
	}
	return copyAcrossNoReplace(src, dst)
}

// copyAcrossNoReplace copies src onto dst, creating dst with O_EXCL so an
// existing (or concurrently created) file is never replaced. Unlike
// copyAcross it writes dst directly: a temp+rename would reintroduce the
// replace that O_EXCL exists to prevent.
func copyAcrossNoReplace(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.OpenFile(dst, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		if errors.Is(err, fs.ErrExist) {
			return ErrDestinationExists
		}
		return err
	}
	cleanup := func() { out.Close(); os.Remove(dst) }

	if _, err := io.Copy(out, in); err != nil {
		cleanup()
		return err
	}
	if err := out.Sync(); err != nil {
		cleanup()
		return err
	}
	if err := out.Close(); err != nil {
		os.Remove(dst)
		return err
	}
	return os.Remove(src)
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
