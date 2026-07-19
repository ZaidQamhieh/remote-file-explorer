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
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"image"
	"image/jpeg"
	"os"
	"path/filepath"

	"github.com/disintegration/imaging"
)

// ErrNotSupported is returned when the source file is not a decodable image
// (e.g. unsupported format, or decode failure).
var ErrNotSupported = errors.New("thumbnail not available for this file")

// jpegQuality is the quality used when re-encoding thumbnails.
const jpegQuality = 80

// Decode bounds (PR-09): reject oversized sources before a full decode so a
// crafted or huge image can't exhaust memory/CPU, and cap concurrent decodes.
// imaging registers the jpeg/png/gif/tiff/bmp decoders image.DecodeConfig uses.
const (
	maxThumbSourceBytes = 64 << 20 // 64 MiB on-disk source cap
	maxThumbPixels      = 40_000_000
)

// decodeSem bounds concurrent full decodes across the process.
var decodeSem = make(chan struct{}, 4)

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

	// Bound the source before decoding (PR-09): on-disk size, then decoded
	// pixel dimensions read from the header without a full decode.
	info, err := os.Stat(srcPath)
	if err != nil {
		return nil, err
	}
	if info.Size() > maxThumbSourceBytes {
		return nil, fmt.Errorf("%w: source exceeds %d bytes", ErrNotSupported, int64(maxThumbSourceBytes))
	}
	cf, err := os.Open(srcPath)
	if err != nil {
		return nil, err
	}
	cfg, _, cfgErr := image.DecodeConfig(cf)
	cf.Close()
	if cfgErr != nil {
		return nil, fmt.Errorf("%w: %v", ErrNotSupported, cfgErr)
	}
	if int64(cfg.Width)*int64(cfg.Height) > maxThumbPixels {
		return nil, fmt.Errorf("%w: %dx%d exceeds pixel budget", ErrNotSupported, cfg.Width, cfg.Height)
	}

	decodeSem <- struct{}{}
	defer func() { <-decodeSem }()

	src, err := imaging.Open(srcPath, imaging.AutoOrientation(true))
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrNotSupported, err)
	}

	thumb := imaging.Fit(src, maxSize, maxSize, imaging.Lanczos)

	tmp, err := os.CreateTemp("", "rfe-thumb-*.jpg")
	if err != nil {
		return nil, fmt.Errorf("create temp file: %w", err)
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)

	if err := jpeg.Encode(tmp, thumb, &jpeg.Options{Quality: jpegQuality}); err != nil {
		tmp.Close()
		return nil, fmt.Errorf("encode jpeg: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return nil, fmt.Errorf("close temp file: %w", err)
	}

	data, err := os.ReadFile(tmpPath)
	if err != nil {
		return nil, fmt.Errorf("read encoded thumbnail: %w", err)
	}
	return data, nil
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
