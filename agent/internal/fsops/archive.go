// Package fsops — archive (compress/extract) operations.
//
// Compress builds a zip from a set of jailed sources; Extract unpacks a
// zip/tar.gz into a jailed destination. Both go through Resolve so the path
// jail and read-only flag apply, and Extract additionally guards every
// archive entry against zip-slip (a "../" entry name escaping destDir).
package fsops

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// ErrArchiveLimit is returned when extraction would exceed the entry-count,
// expanded-byte, or compression-ratio budget.
var ErrArchiveLimit = errors.New("archive exceeds extraction limits")

const (
	maxArchiveEntries        = 100_000
	maxArchiveExpandedBytes  = int64(20 << 30)
	maxArchiveExpansionRatio = int64(200)
	archiveExpansionSlack    = int64(10 << 20)
)

type archiveBudget struct {
	entries int
	bytes   int64
	limit   int64
}

func newArchiveBudget(archivePath string) (*archiveBudget, error) {
	info, err := os.Stat(archivePath)
	if err != nil {
		return nil, err
	}
	limit := maxArchiveExpandedBytes
	if info.Size() <= (maxArchiveExpandedBytes-archiveExpansionSlack)/maxArchiveExpansionRatio {
		limit = info.Size()*maxArchiveExpansionRatio + archiveExpansionSlack
	}
	return &archiveBudget{limit: limit}, nil
}

func (b *archiveBudget) reserve(size int64) error {
	b.entries++
	if b.entries > maxArchiveEntries {
		return fmt.Errorf("%w: more than %d entries", ErrArchiveLimit, maxArchiveEntries)
	}
	if size < 0 || size > b.limit-b.bytes {
		return fmt.Errorf("%w: expanded data exceeds %d bytes", ErrArchiveLimit, b.limit)
	}
	b.bytes += size
	return nil
}

// Compress creates a zip archive at destPath containing each of sources
// (files or directories, recursively). All sources and destPath are
// jail-checked via Resolve. If destPath already exists it is auto-renamed
// ("keep both"), so the call never clobbers an existing file. The archive is
// written to a temp file in the destination directory and renamed into place
// on success, so a failure can't leave a partial .zip behind. Returns the
// created archive's Entry.
func (o *Ops) Compress(sources []string, destPath string) (*Entry, error) {
	if o.settings.IsReadOnly() {
		return nil, ErrReadOnly
	}
	if len(sources) == 0 {
		return nil, fmt.Errorf("%w: no sources", ErrNotFound)
	}

	resDest, err := o.Resolve(destPath)
	if err != nil {
		return nil, err
	}
	// Resolve (and jail-check) every source up front so a bad path fails the
	// whole operation before any bytes are written.
	resolved := make([]string, 0, len(sources))
	for _, s := range sources {
		rs, err := o.Resolve(s)
		if err != nil {
			return nil, err
		}
		resolved = append(resolved, rs)
	}

	if _, err := os.Stat(resDest); err == nil {
		resDest = autoRename(resDest)
	}
	dir := filepath.Dir(resDest)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}

	tmp, err := os.CreateTemp(dir, "."+filepath.Base(resDest)+".rfe-tmp-*")
	if err != nil {
		return nil, err
	}
	tmpName := tmp.Name()
	cleanup := func() { _ = os.Remove(tmpName) }

	zw := zip.NewWriter(tmp)
	for _, src := range resolved {
		if err := addToZip(zw, src); err != nil {
			zw.Close()
			tmp.Close()
			cleanup()
			return nil, err
		}
	}
	if err := zw.Close(); err != nil {
		tmp.Close()
		cleanup()
		return nil, err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		cleanup()
		return nil, err
	}
	if err := tmp.Close(); err != nil {
		cleanup()
		return nil, err
	}
	if err := os.Rename(tmpName, resDest); err != nil {
		cleanup()
		return nil, err
	}
	return o.Meta(resDest)
}

// addToZip walks src (a file or directory) and writes its entries into zw.
// Entry names are relative to src's parent, so the top-level file/folder name
// is preserved inside the archive. Non-regular files (symlinks, devices) are
// skipped.
func addToZip(zw *zip.Writer, src string) error {
	base := filepath.Dir(src)
	return filepath.Walk(src, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(base, p)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)

		if info.IsDir() {
			if rel == "." {
				return nil
			}
			_, err := zw.Create(rel + "/")
			return err
		}
		if !info.Mode().IsRegular() {
			return nil
		}

		hdr, err := zip.FileInfoHeader(info)
		if err != nil {
			return err
		}
		hdr.Name = rel
		hdr.Method = zip.Deflate
		w, err := zw.CreateHeader(hdr)
		if err != nil {
			return err
		}
		f, err := os.Open(p)
		if err != nil {
			return err
		}
		defer f.Close()
		_, err = io.Copy(w, f)
		return err
	})
}

// Extract unpacks archivePath (zip, tar.gz or tgz) into destDir. Both paths are
// jail-checked. Extraction happens in a private staging directory and is
// published only after success. Existing real directories are supported, but
// archive top-level entries may not collide with their contents; this prevents
// existing symlinks or files from redirecting or being overwritten.
func (o *Ops) Extract(archivePath, destDir string) (*Entry, error) {
	if o.settings.IsReadOnly() {
		return nil, ErrReadOnly
	}
	resArchive, err := o.Resolve(archivePath)
	if err != nil {
		return nil, err
	}
	if _, err := os.Stat(resArchive); err != nil {
		if os.IsNotExist(err) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	resDest, err := o.Resolve(destDir)
	if err != nil {
		return nil, err
	}
	lower := strings.ToLower(resArchive)
	if !strings.HasSuffix(lower, ".zip") && !strings.HasSuffix(lower, ".tar.gz") && !strings.HasSuffix(lower, ".tgz") {
		return nil, fmt.Errorf("%w: %s", ErrUnsupported, filepath.Base(resArchive))
	}

	parent := filepath.Dir(resDest)
	if err := os.MkdirAll(parent, 0o755); err != nil {
		return nil, err
	}
	staging, err := os.MkdirTemp(parent, "."+filepath.Base(resDest)+".rfe-extract-*")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(staging)
	budget, err := newArchiveBudget(resArchive)
	if err != nil {
		return nil, err
	}

	switch {
	case strings.HasSuffix(lower, ".zip"):
		err = extractZip(resArchive, staging, budget)
	case strings.HasSuffix(lower, ".tar.gz"), strings.HasSuffix(lower, ".tgz"):
		err = extractTarGz(resArchive, staging, budget)
	}
	if err != nil {
		return nil, err
	}
	if err := publishExtractedTree(staging, resDest); err != nil {
		return nil, err
	}
	return o.Meta(resDest)
}

// publishExtractedTree merges the fully validated staging tree into dest
// without following existing links or replacing existing entries. Top-level
// names are preflighted before the first publish; if publishing later fails,
// entries created by this call are removed again.
func publishExtractedTree(staging, dest string) error {
	destInfo, err := os.Lstat(dest)
	createdDest := false
	switch {
	case os.IsNotExist(err):
		if err := os.Mkdir(dest, 0o755); err != nil {
			return err
		}
		createdDest = true
	case err != nil:
		return err
	case destInfo.Mode()&os.ModeSymlink != 0 || !destInfo.IsDir():
		return ErrConflict
	}

	entries, err := os.ReadDir(staging)
	if err != nil {
		if createdDest {
			_ = os.Remove(dest)
		}
		return err
	}
	for _, entry := range entries {
		if _, err := os.Lstat(filepath.Join(dest, entry.Name())); err == nil {
			if createdDest {
				_ = os.Remove(dest)
			}
			return ErrConflict
		} else if !os.IsNotExist(err) {
			if createdDest {
				_ = os.Remove(dest)
			}
			return err
		}
	}

	published := make([]string, 0, len(entries))
	for _, entry := range entries {
		target := filepath.Join(dest, entry.Name())
		if err := publishExtractedEntry(filepath.Join(staging, entry.Name()), target); err != nil {
			for _, path := range published {
				_ = os.RemoveAll(path)
			}
			if createdDest {
				_ = os.Remove(dest)
			}
			if os.IsExist(err) {
				return ErrConflict
			}
			return err
		}
		published = append(published, target)
	}
	return nil
}

func publishExtractedEntry(source, target string) error {
	info, err := os.Lstat(source)
	if err != nil {
		return err
	}
	if info.IsDir() {
		if err := os.Mkdir(target, info.Mode().Perm()); err != nil {
			return err
		}
		entries, err := os.ReadDir(source)
		if err != nil {
			_ = os.Remove(target)
			return err
		}
		for _, entry := range entries {
			if err := publishExtractedEntry(filepath.Join(source, entry.Name()), filepath.Join(target, entry.Name())); err != nil {
				_ = os.RemoveAll(target)
				return err
			}
		}
		return os.Remove(source)
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("%w: unsupported staged entry", ErrForbidden)
	}
	if err := os.Link(source, target); err != nil {
		return err
	}
	return os.Remove(source)
}

// safeJoin joins name onto destDir and guarantees the result stays within
// destDir, defeating zip-slip (entries like "../../etc/passwd"). filepath.Join
// cleans the path (collapsing "..") and isUnder then rejects anything that
// climbed out of the destination.
func safeJoin(destDir, name string) (string, error) {
	target := filepath.Join(destDir, name)
	if !isUnder(target, destDir) {
		return "", fmt.Errorf("%w: archive entry escapes destination: %s", ErrForbidden, name)
	}
	return target, nil
}

func extractZip(archive, dest string, budget *archiveBudget) error {
	zr, err := zip.OpenReader(archive)
	if err != nil {
		return err
	}
	defer zr.Close()

	for _, f := range zr.File {
		size := int64(0)
		if !f.FileInfo().IsDir() && f.Mode().IsRegular() {
			if f.UncompressedSize64 > uint64(maxArchiveExpandedBytes) {
				return fmt.Errorf("%w: entry %s is too large", ErrArchiveLimit, f.Name)
			}
			size = int64(f.UncompressedSize64)
		}
		if err := budget.reserve(size); err != nil {
			return err
		}
		target, err := safeJoin(dest, f.Name)
		if err != nil {
			return err
		}
		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(target, 0o755); err != nil {
				return err
			}
			continue
		}
		if !f.Mode().IsRegular() {
			continue // skip symlinks / devices
		}
		if err := writeZipFile(f, target); err != nil {
			return err
		}
	}
	return nil
}

func writeZipFile(f *zip.File, target string) error {
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return err
	}
	mode := f.Mode().Perm()
	if mode == 0 {
		mode = 0o644
	}
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer rc.Close()
	out, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, rc)
	return err
}

func extractTarGz(archive, dest string, budget *archiveBudget) error {
	f, err := os.Open(archive)
	if err != nil {
		return err
	}
	defer f.Close()
	gz, err := gzip.NewReader(f)
	if err != nil {
		return err
	}
	defer gz.Close()

	tr := tar.NewReader(gz)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		size := int64(0)
		if hdr.Typeflag == tar.TypeReg {
			size = hdr.Size
		}
		if err := budget.reserve(size); err != nil {
			return err
		}
		target, err := safeJoin(dest, hdr.Name)
		if err != nil {
			return err
		}
		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0o755); err != nil {
				return err
			}
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			mode := os.FileMode(hdr.Mode).Perm()
			if mode == 0 {
				mode = 0o644
			}
			out, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
			if err != nil {
				return err
			}
			if _, err := io.Copy(out, tr); err != nil { //nolint:gosec // size bounded by caller's own files
				out.Close()
				return err
			}
			out.Close()
		default:
			continue // skip symlinks / devices / fifos
		}
	}
	return nil
}
