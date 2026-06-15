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

func extractZip(archive, dest string) error {
	zr, err := zip.OpenReader(archive)
	if err != nil {
		return err
	}
	defer zr.Close()

	for _, f := range zr.File {
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
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
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
