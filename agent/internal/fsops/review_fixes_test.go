package fsops

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestIsUnder_FilesystemRoot(t *testing.T) {
	sep := string(filepath.Separator)
	if !isUnder(sep+"a"+sep+"b", sep) {
		t.Fatalf("path below the filesystem root must be under it")
	}
	if isUnder(sep+"ab", sep+"a") {
		t.Fatalf("sibling with a shared prefix must not be under the root")
	}
}

func TestCopy_FolderIntoItselfRejected(t *testing.T) {
	ops, root := setupJail(t)
	src := filepath.Join(root, "a")
	sub := filepath.Join(src, "sub")
	if err := os.MkdirAll(sub, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, dup := range []bool{false, true} {
		for _, dest := range []string{sub, src} {
			res := ops.Copy([]string{src}, dest, dup, false)
			if len(res) != 1 || res[0].OK {
				t.Fatalf("copy into itself (dest=%s dup=%v) must fail: %+v", dest, dup, res)
			}
		}
	}
	if _, err := os.Stat(filepath.Join(sub, "a")); !os.IsNotExist(err) {
		t.Fatalf("no nested copy may be created, stat err: %v", err)
	}
}

func TestCopy_DuplicateLongNameTerminates(t *testing.T) {
	ops, root := setupJail(t)
	name := strings.Repeat("x", 254)
	src := filepath.Join(root, name)
	if err := os.WriteFile(src, []byte("d"), 0o644); err != nil {
		t.Skipf("filesystem rejects long names: %v", err)
	}
	done := make(chan struct{})
	go func() {
		ops.Copy([]string{src}, root, true, false)
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("duplicate copy of a 254-byte name did not terminate")
	}
}

func TestUniqueTrashName_LongNameTerminates(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(trashFilesDir(dir), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(trashInfoDir(dir), 0o755); err != nil {
		t.Fatal(err)
	}
	name := strings.Repeat("x", 254)
	if err := os.WriteFile(filepath.Join(trashFilesDir(dir), name), nil, 0o644); err != nil {
		t.Skipf("filesystem rejects long names: %v", err)
	}
	done := make(chan struct{})
	go func() {
		uniqueTrashName(dir, name)
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("uniqueTrashName did not terminate")
	}
}
