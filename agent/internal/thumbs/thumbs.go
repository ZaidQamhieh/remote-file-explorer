// Package thumbs renders and caches JPEG thumbnails for image files.
//
// Rendering is done with a pure-Go decoder/resizer (github.com/disintegration/imaging),
// which supports JPEG, PNG, and GIF source images (no WebP/HEIC/etc — callers
// should treat ErrNotSupported as "no thumbnail available" and fall back to a
// generic icon). Results are cached on disk under <cacheDir> keyed by a hash of
// the source path, the requested size, and the source file's modification time,
// so re-rendering only happens when the source changes or the size differs.
package thumbs

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"image"
	"image/jpeg"
	"io"
	"os"
	"path/filepath"

	"github.com/disintegration/imaging"
)

// ErrNotSupported is returned when the source file is not a decodable image
// (e.g. unsupported format, or decode failure).
var ErrNotSupported = errors.New("thumbnail not available for this file")

// ErrResourceLimit is returned before full decode when a source would exceed
// the renderer's file or decoded-pixel budget.
var ErrResourceLimit = errors.New("thumbnail source exceeds resource limits")

// jpegQuality is the quality used when re-encoding thumbnails.
const (
	jpegQuality     = 80
	maxSourceBytes  = 64 << 20
	maxSourcePixels = 40_000_000
)

// Image decoders can be CPU- and memory-heavy even for valid inputs. Bound
// concurrent decodes across all renderers in this process.
var renderSlots = make(chan struct{}, 2)

// Renderer renders and caches image thumbnails on disk.
type Renderer struct {
	cacheDir string
}

// New creates a Renderer that stores cached thumbnails under cacheDir.
// The directory is created if it doesn't already exist.
func New(cacheDir string) (*Renderer, error) {
	if err := os.MkdirAll(cacheDir, 0o700); err != nil {
		return nil, fmt.Errorf("create thumb cache dir: %w", err)
	}
	return &Renderer{cacheDir: cacheDir}, nil
}

// Get returns JPEG-encoded thumbnail bytes for srcPath, resized so its
// longest side is at most maxSize pixels.
//
// On a cache hit the cached bytes are returned directly. On a miss the image
// is decoded, resized, re-encoded as JPEG, written to the cache (atomically),
// and returned.
//
// Returns ErrNotSupported (wrapped) if srcPath isn't a decodable image.
func (rn *Renderer) Get(srcPath string, maxSize int) ([]byte, error) {
	info, err := os.Stat(srcPath)
	if err != nil {
		return nil, err
	}
	if info.IsDir() {
		return nil, fmt.Errorf("%w: directory", ErrNotSupported)
	}

	cachePath := rn.cachePath(srcPath, maxSize, info.ModTime().UnixNano())

	if data, err := os.ReadFile(cachePath); err == nil {
		return data, nil
	}

	data, err := Render(srcPath, maxSize)
	if err != nil {
		return nil, err
	}

	if err := writeAtomic(cachePath, data); err != nil {
		// Cache write failures shouldn't prevent serving the thumbnail —
		// just log-worthy, not fatal. We still return the rendered bytes.
		return data, nil
	}

	return data, nil
}

// Render decodes the image at srcPath, resizes it so its longest side is at
// most maxSize pixels (preserving aspect ratio, never upscaling beyond the
// original), and re-encodes it as a JPEG at jpegQuality.
//
// Returns ErrNotSupported (wrapped) if the file can't be decoded as an image.
func Render(srcPath string, maxSize int) ([]byte, error) {
	if maxSize <= 0 {
		maxSize = 256
	}

	info, err := os.Stat(srcPath)
	if err != nil {
		return nil, err
	}
	if info.Size() > maxSourceBytes {
		return nil, fmt.Errorf("%w: source is %d bytes (max %d)", ErrResourceLimit, info.Size(), maxSourceBytes)
	}
	f, err := os.Open(srcPath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	config, _, err := image.DecodeConfig(io.NewSectionReader(f, 0, maxSourceBytes+1))
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrNotSupported, err)
	}
	if config.Width <= 0 || config.Height <= 0 || int64(config.Width) > maxSourcePixels/int64(config.Height) {
		return nil, fmt.Errorf("%w: dimensions %dx%d", ErrResourceLimit, config.Width, config.Height)
	}

	renderSlots <- struct{}{}
	defer func() { <-renderSlots }()
	src, err := imaging.Decode(io.NewSectionReader(f, 0, maxSourceBytes+1), imaging.AutoOrientation(true))
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrNotSupported, err)
	}

	thumb := imaging.Fit(src, maxSize, maxSize, imaging.Lanczos)
	var encoded bytes.Buffer
	if err := jpeg.Encode(&encoded, thumb, &jpeg.Options{Quality: jpegQuality}); err != nil {
		return nil, fmt.Errorf("encode jpeg: %w", err)
	}
	return encoded.Bytes(), nil
}

// cachePath returns the on-disk path for a cached thumbnail keyed by the
// source path, requested size, and the source's modification time (so stale
// cache entries are naturally bypassed when the source file changes).
func (rn *Renderer) cachePath(srcPath string, maxSize int, mtimeNano int64) string {
	sum := sha256.Sum256([]byte(srcPath))
	key := fmt.Sprintf("%s_%d_%d.jpg", hex.EncodeToString(sum[:]), maxSize, mtimeNano)
	return filepath.Join(rn.cacheDir, key)
}

// writeAtomic writes data to path via a temp file + rename, matching the
// atomic-write pattern used elsewhere in the agent (see internal/transfer).
func writeAtomic(path string, data []byte) error {
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, ".thumb-*.tmp")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()

	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		os.Remove(tmpPath)
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpPath)
		return err
	}
	if err := os.Rename(tmpPath, path); err != nil {
		os.Remove(tmpPath)
		return err
	}
	return nil
}
