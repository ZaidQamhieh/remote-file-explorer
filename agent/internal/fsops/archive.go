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

// Extract unpacks archivePath (zip, tar.gz or tgz) into destDir, which is
// created if absent. Both paths are jail-checked. Each archive entry's target
// is validated to stay within destDir (zip-slip guard); non-regular entries
// (symlinks, devices) are skipped. Returns destDir's Entry.
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
	if err := os.MkdirAll(resDest, 0o755); err != nil {
		return nil, err
	}

	lower := strings.ToLower(resArchive)
	switch {
	case strings.HasSuffix(lower, ".zip"):
		err = extractZip(resArchive, resDest)
	case strings.HasSuffix(lower, ".tar.gz"), strings.HasSuffix(lower, ".tgz"):
		err = extractTarGz(resArchive, resDest)
	default:
		return nil, fmt.Errorf("%w: %s", ErrUnsupported, filepath.Base(resArchive))
	}
	if err != nil {
		return nil, err
	}
	return o.Meta(resDest)
}

// Archive extraction bounds (PR-07): a paired client can supply a crafted
// archive, so cap entry count and total expanded bytes to defeat zip/tar
// bombs. These are process-wide ceilings, not per-user quotas.
const (
	maxArchiveEntries    = 100_000
	maxArchiveTotalBytes = int64(2) << 30 // 2 GiB expanded
)

// ErrArchiveTooLarge is returned when an archive exceeds the extraction bounds.
var ErrArchiveTooLarge = errors.New("archive exceeds extraction limits")

// copyBounded copies src into dst, debiting *remaining and failing if the
// archive's total expanded size would exceed the budget. It meters the actual
// decompressed stream rather than trusting a header, so a bomb with lying
// declared sizes is still caught.
func copyBounded(dst io.Writer, src io.Reader, remaining *int64) error {
	limited := io.LimitReader(src, *remaining+1)
	n, err := io.Copy(dst, limited)
	if err != nil {
		return err
	}
	if n > *remaining {
		return fmt.Errorf("%w: expanded size over %d bytes", ErrArchiveTooLarge, maxArchiveTotalBytes)
	}
	*remaining -= n
	return nil
}

// safeJoin joins name onto destDir and guarantees the result stays within
// destDir, defeating zip-slip (entries like "../../etc/passwd"). filepath.Join
// cleans the path (collapsing "..") and isUnder then rejects anything that
// climbed out of the destination.
//
// isUnder alone is only a *lexical* guarantee, which is not the same as the
// write landing inside destDir: if any existing component of the path is a
// symlink, "destDir/sub/x" can be a perfectly innocent-looking name that the
// OS resolves to /etc/x when MkdirAll or O_CREATE follows it. Both extractors
// join through here, so the parent-chain check lives here too (PR-06).
func safeJoin(destDir, name string) (string, error) {
	target := filepath.Join(destDir, name)
	if !isUnder(target, destDir) {
		return "", fmt.Errorf("%w: archive entry escapes destination: %s", ErrForbidden, name)
	}
	if err := checkNoSymlinkParent(destDir, target); err != nil {
		return "", err
	}
	return target, nil
}

// checkNoSymlinkParent rejects target if any existing component between
// destDir and target (inclusive) is a symlink. Archive entries that ARE links
// are already skipped by the extractors; this covers links that were sitting
// in the destination beforehand, which the entry names alone can't reveal.
//
// ponytail: Lstat-then-write is a check/use race — an attacker able to plant a
// symlink into the destination *during* extraction can still win it. Closing
// that needs descriptor-relative openat traversal (the SecureFS refactor the
// audit asks for), not a stricter check here.
func checkNoSymlinkParent(destDir, target string) error {
	rel, err := filepath.Rel(destDir, target)
	if err != nil {
		return fmt.Errorf("%w: archive entry escapes destination: %s", ErrForbidden, target)
	}
	cur := destDir
	for _, part := range strings.Split(rel, string(os.PathSeparator)) {
		cur = filepath.Join(cur, part)
		fi, err := os.Lstat(cur)
		if os.IsNotExist(err) {
			// Nothing from here down exists yet — the extractor creates it.
			return nil
		}
		if err != nil {
			return err
		}
		if fi.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("%w: archive entry path crosses a symlink: %s", ErrForbidden, rel)
		}
	}
	return nil
}

func extractZip(archive, dest string) error {
	zr, err := zip.OpenReader(archive)
	if err != nil {
		return err
	}
	defer zr.Close()

	remaining := maxArchiveTotalBytes
	entries := 0
	for _, f := range zr.File {
		entries++
		if entries > maxArchiveEntries {
			return fmt.Errorf("%w: over %d entries", ErrArchiveTooLarge, maxArchiveEntries)
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
		if err := writeZipFile(f, target, &remaining); err != nil {
			return err
		}
	}
	return nil
}

func writeZipFile(f *zip.File, target string, remaining *int64) error {
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
	return copyBounded(out, rc, remaining)
}

func extractTarGz(archive, dest string) error {
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
	remaining := maxArchiveTotalBytes
	entries := 0
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		entries++
		if entries > maxArchiveEntries {
			return fmt.Errorf("%w: over %d entries", ErrArchiveTooLarge, maxArchiveEntries)
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
			if err := copyBounded(out, tr, &remaining); err != nil {
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
