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
	kflate "github.com/klauspost/compress/flate"
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

	resDest, err := o.access(destPath)
	if err != nil {
		return nil, err
	}
	defer resDest.close()
	// Resolve (and jail-check) every source up front so a bad path fails the
	// whole operation before any bytes are written.
	resolved := make([]*securePath, 0, len(sources))
	for _, s := range sources {
		rs, err := o.access(s)
		if err != nil {
			for _, opened := range resolved {
				opened.close()
			}
			return nil, err
		}
		resolved = append(resolved, rs)
	}
	defer func() {
		for _, opened := range resolved {
			opened.close()
		}
	}()

	if _, err := resDest.stat(); err == nil {
		renamed := autoRenameSecure(resDest)
		resDest.full = renamed.full
		resDest.name = renamed.name
	}
	if err := resDest.parent().mkdirAll(0o755); err != nil {
		return nil, err
	}

	tmpPath, tmp, err := resDest.createTemp("." + filepath.Base(resDest.full) + ".rfe-tmp-*")
	if err != nil {
		return nil, err
	}
	cleanup := func() { _ = tmpPath.remove() }

	zw := zip.NewWriter(tmp)
	// klauspost's deflate writes the same format about 1.5x faster than the standard library at a ~1% larger size.
	zw.RegisterCompressor(zip.Deflate, func(w io.Writer) (io.WriteCloser, error) { return kflate.NewWriter(w, zipDeflateLevel) })
	for _, src := range resolved {
		if err := addToZipSecure(zw, src); err != nil {
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
	if err := tmpPath.renameTo(resDest); err != nil {
		cleanup()
		return nil, err
	}
	return o.Meta(resDest.full)
}

// zipDeflateLevel is klauspost's level 5: 51 MB/s against 33 MB/s for the standard library's default on a
// 221 MB mixed corpus, within about 1% of its output size (see TestZipCompressorSpeed).
const zipDeflateLevel = 5

func addToZipSecure(zw *zip.Writer, src *securePath) error {
	base := filepath.Base(src.full)
	return addToZipSecureEntry(zw, src, base)
}

func addToZipSecureEntry(zw *zip.Writer, src *securePath, name string) error {
	info, err := src.lstat()
	if err != nil {
		return err
	}
	if info.IsDir() {
		if name != "" {
			if _, err := zw.Create(filepath.ToSlash(name) + "/"); err != nil {
				return err
			}
		}
		dir, err := src.open()
		if err != nil {
			return err
		}
		entries, readErr := dir.Readdir(-1)
		closeErr := dir.Close()
		if readErr != nil {
			return readErr
		}
		if closeErr != nil {
			return closeErr
		}
		for _, entry := range entries {
			childName := filepath.Join(name, entry.Name())
			if err := addToZipSecureEntry(zw, src.child(entry.Name()), childName); err != nil {
				return err
			}
		}
		return nil
	}
	if !info.Mode().IsRegular() {
		return nil
	}
	hdr, err := zip.FileInfoHeader(info)
	if err != nil {
		return err
	}
	hdr.Name = filepath.ToSlash(name)
	hdr.Method = zip.Deflate
	w, err := zw.CreateHeader(hdr)
	if err != nil {
		return err
	}
	f, err := src.open()
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = io.Copy(w, f)
	return err
}

// Extract unpacks archivePath (zip, tar.gz or tgz) into destDir, which is
// created if absent. Both paths are jail-checked. Each archive entry's target
// is validated to stay within destDir (zip-slip guard); non-regular entries
// (symlinks, devices) are skipped. Returns destDir's Entry.
func (o *Ops) Extract(archivePath, destDir string) (*Entry, error) {
	if o.settings.IsReadOnly() {
		return nil, ErrReadOnly
	}
	resArchive, err := o.access(archivePath)
	if err != nil {
		return nil, err
	}
	defer resArchive.close()
	if _, err := resArchive.stat(); err != nil {
		if os.IsNotExist(err) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	resDest, err := o.access(destDir)
	if err != nil {
		return nil, err
	}
	defer resDest.close()
	if err := resDest.mkdirAll(0o755); err != nil {
		return nil, err
	}

	lower := strings.ToLower(resArchive.full)
	switch {
	case strings.HasSuffix(lower, ".zip"):
		err = extractZipSecure(resArchive, resDest)
	case strings.HasSuffix(lower, ".tar.gz"), strings.HasSuffix(lower, ".tgz"):
		err = extractTarGzSecure(resArchive, resDest)
	default:
		return nil, fmt.Errorf("%w: %s", ErrUnsupported, filepath.Base(resArchive.full))
	}
	if err != nil {
		return nil, err
	}
	return o.Meta(resDest.full)
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
// isUnder alone is only a lexical guarantee, so the secure extractors also
// perform every filesystem operation through the destination's os.Root handle.
// This check preserves the prior policy of rejecting pre-existing symlink
// parents; the handle closes the check/use race.
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

func safeJoinSecure(dest *securePath, name string) (*securePath, error) {
	target, err := safeJoin(dest.full, name)
	if err != nil {
		return nil, err
	}
	rel, err := filepath.Rel(dest.full, target)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
		return nil, fmt.Errorf("%w: archive entry escapes destination: %s", ErrForbidden, name)
	}
	return &securePath{full: target, root: dest.root, name: filepath.Join(dest.name, rel)}, nil
}

func createArchiveFile(path *securePath, mode os.FileMode) (*os.File, error) {
	if err := path.parent().mkdirAll(0o755); err != nil {
		return nil, err
	}
	if info, err := path.lstat(); err == nil {
		if info.IsDir() {
			return nil, fmt.Errorf("archive file conflicts with a directory")
		}
		if err := path.remove(); err != nil {
			return nil, err
		}
	} else if !os.IsNotExist(err) {
		return nil, err
	}
	return path.openFile(os.O_CREATE|os.O_EXCL|os.O_WRONLY, mode)
}

func extractZipSecure(archive, dest *securePath) error {
	input, err := archive.open()
	if err != nil {
		return err
	}
	defer input.Close()
	info, err := archive.stat()
	if err != nil {
		return err
	}
	zr, err := zip.NewReader(input, info.Size())
	if err != nil {
		return err
	}
	remaining := maxArchiveTotalBytes
	for i, f := range zr.File {
		if i >= maxArchiveEntries {
			return fmt.Errorf("%w: over %d entries", ErrArchiveTooLarge, maxArchiveEntries)
		}
		target, err := safeJoinSecure(dest, f.Name)
		if err != nil {
			return err
		}
		if f.FileInfo().IsDir() {
			if err := target.mkdirAll(0o755); err != nil {
				return err
			}
			continue
		}
		if !f.Mode().IsRegular() {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return err
		}
		mode := f.Mode().Perm()
		if mode == 0 {
			mode = 0o644
		}
		out, err := createArchiveFile(target, mode)
		if err == nil {
			err = copyBounded(out, rc, &remaining)
			closeErr := out.Close()
			if err == nil {
				err = closeErr
			}
		}
		rc.Close()
		if err != nil {
			return err
		}
	}
	return nil
}

func extractTarGzSecure(archive, dest *securePath) error {
	input, err := archive.open()
	if err != nil {
		return err
	}
	defer input.Close()
	gz, err := gzip.NewReader(input)
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
		target, err := safeJoinSecure(dest, hdr.Name)
		if err != nil {
			return err
		}
		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := target.mkdirAll(0o755); err != nil {
				return err
			}
		case tar.TypeReg:
			mode := os.FileMode(hdr.Mode).Perm()
			if mode == 0 {
				mode = 0o644
			}
			out, err := createArchiveFile(target, mode)
			if err != nil {
				return err
			}
			copyErr := copyBounded(out, tr, &remaining)
			closeErr := out.Close()
			if copyErr != nil {
				return copyErr
			}
			if closeErr != nil {
				return closeErr
			}
		default:
			continue
		}
	}
	return nil
}
