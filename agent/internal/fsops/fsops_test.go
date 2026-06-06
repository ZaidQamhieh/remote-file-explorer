package fsops

import (
	"os"
	"path/filepath"
	"testing"
)

// setupJail creates a temp directory as the jail root and returns
// an Ops restricted to it, plus a cleanup function.
func setupJail(t *testing.T) (*Ops, string) {
	t.Helper()
	root := t.TempDir()
	ops := New([]string{root}, false)
	return ops, root
}

// TestResolve_AllowsInsideJail verifies a normal path inside the jail is accepted.
func TestResolve_AllowsInsideJail(t *testing.T) {
	ops, root := setupJail(t)
	path := filepath.Join(root, "subdir", "file.txt")
	got, err := ops.Resolve(path)
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}
	// Clean path should be returned.
	if filepath.Clean(got) != filepath.Clean(path) {
		t.Fatalf("expected %s, got %s", path, got)
	}
}

// TestResolve_BlocksTraversal verifies ../ escapes are rejected.
func TestResolve_BlocksTraversal(t *testing.T) {
	ops, root := setupJail(t)
	// Construct a path that looks inside but traverses out.
	evil := filepath.Join(root, "subdir", "..", "..", "etc", "passwd")
	_, err := ops.Resolve(evil)
	if err == nil {
		t.Fatal("expected error for traversal path, got nil")
	}
}

// TestResolve_BlocksSymlinkEscape verifies a symlink pointing outside the
// jail is rejected.
func TestResolve_BlocksSymlinkEscape(t *testing.T) {
	ops, root := setupJail(t)

	// Create a target outside the jail.
	outside := t.TempDir()

	// Create a symlink inside the jail pointing to outside.
	link := filepath.Join(root, "escape-link")
	if err := os.Symlink(outside, link); err != nil {
		t.Fatalf("symlink: %v", err)
	}

	// Attempting to resolve through the symlink should be rejected.
	_, err := ops.Resolve(link)
	if err == nil {
		t.Fatal("expected error for symlink escape, got nil")
	}
}

// TestResolve_RelativePathRejected verifies relative paths are always rejected.
func TestResolve_RelativePathRejected(t *testing.T) {
	ops, _ := setupJail(t)
	_, err := ops.Resolve("relative/path")
	if err == nil {
		t.Fatal("expected error for relative path, got nil")
	}
}

// TestResolve_NoJailAllowsAnything verifies that an empty allowedRoots
// permits any absolute path.
func TestResolve_NoJailAllowsAnything(t *testing.T) {
	ops := New(nil, false)
	_, err := ops.Resolve("/tmp")
	if err != nil {
		t.Fatalf("expected no error for /tmp with no jail, got: %v", err)
	}
}

// TestCreateAndDelete exercises CreateFolder, CreateFile, ListDir, and Delete.
func TestCreateAndDelete(t *testing.T) {
	ops, root := setupJail(t)

	// Create a folder.
	dirPath := filepath.Join(root, "mydir")
	entry, err := ops.CreateFolder(dirPath)
	if err != nil {
		t.Fatalf("CreateFolder: %v", err)
	}
	if !entry.IsDir {
		t.Fatal("expected isDir=true")
	}

	// Create a file inside.
	filePath := filepath.Join(root, "mydir", "hello.txt")
	fileEntry, err := ops.CreateFile(filePath)
	if err != nil {
		t.Fatalf("CreateFile: %v", err)
	}
	if fileEntry.IsDir {
		t.Fatal("expected isDir=false")
	}

	// List the directory.
	listing, err := ops.ListDir(dirPath, "", 100)
	if err != nil {
		t.Fatalf("ListDir: %v", err)
	}
	if len(listing.Entries) != 1 || listing.Entries[0].Name != "hello.txt" {
		t.Fatalf("unexpected listing: %+v", listing.Entries)
	}

	// Delete the file.
	results := ops.Delete([]string{filePath})
	if len(results) != 1 || !results[0].OK {
		t.Fatalf("Delete failed: %+v", results)
	}
}

// TestReadOnly verifies that write ops are rejected when readOnly=true.
func TestReadOnly(t *testing.T) {
	root := t.TempDir()
	ops := New([]string{root}, true)

	_, err := ops.CreateFolder(filepath.Join(root, "nope"))
	if err == nil {
		t.Fatal("expected read-only error")
	}

	_, err = ops.CreateFile(filepath.Join(root, "nope.txt"))
	if err == nil {
		t.Fatal("expected read-only error")
	}

	results := ops.Delete([]string{filepath.Join(root, "x")})
	if results[0].OK || results[0].Error == nil {
		t.Fatal("expected read-only batch error")
	}
}

// TestListDir_Pagination verifies cursor-based pagination.
func TestListDir_Pagination(t *testing.T) {
	ops, root := setupJail(t)

	// Create 5 files: a.txt through e.txt.
	for _, name := range []string{"a.txt", "b.txt", "c.txt", "d.txt", "e.txt"} {
		f, err := os.Create(filepath.Join(root, name))
		if err != nil {
			t.Fatalf("create %s: %v", name, err)
		}
		f.Close()
	}

	// First page: limit 2.
	listing, err := ops.ListDir(root, "", 2)
	if err != nil {
		t.Fatalf("ListDir page 1: %v", err)
	}
	if len(listing.Entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(listing.Entries))
	}
	if listing.NextCursor == nil {
		t.Fatal("expected nextCursor to be set")
	}

	// Second page.
	listing2, err := ops.ListDir(root, *listing.NextCursor, 2)
	if err != nil {
		t.Fatalf("ListDir page 2: %v", err)
	}
	if len(listing2.Entries) != 2 {
		t.Fatalf("expected 2 entries on page 2, got %d", len(listing2.Entries))
	}

	// Third (last) page.
	listing3, err := ops.ListDir(root, *listing2.NextCursor, 2)
	if err != nil {
		t.Fatalf("ListDir page 3: %v", err)
	}
	if len(listing3.Entries) != 1 {
		t.Fatalf("expected 1 entry on last page, got %d", len(listing3.Entries))
	}
	if listing3.NextCursor != nil {
		t.Fatal("expected nextCursor to be nil on last page")
	}
}
