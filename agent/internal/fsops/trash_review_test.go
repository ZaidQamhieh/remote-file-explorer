package fsops

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"testing"
)

// A cross-device rename must be recognised (directly or wrapped in a LinkError)
// so the trash move falls back to copy+remove; unrelated errors must not be.
func TestIsCrossDevice(t *testing.T) {
	if !isCrossDevice(syscall.EXDEV) {
		t.Fatal("bare EXDEV must be cross-device")
	}
	if !isCrossDevice(&os.LinkError{Op: "rename", Old: "a", New: "b", Err: syscall.EXDEV}) {
		t.Fatal("LinkError wrapping EXDEV must be cross-device")
	}
	if !isCrossDevice(fmt.Errorf("wrapped: %w", &os.LinkError{Err: syscall.EXDEV})) {
		t.Fatal("wrapped LinkError must be cross-device")
	}
	for _, err := range []error{nil, errors.New("boom"), os.ErrNotExist, syscall.EACCES, &os.LinkError{Err: syscall.ENOENT}} {
		if isCrossDevice(err) {
			t.Fatalf("%v must not be cross-device", err)
		}
	}
	// Errno 17 is ERROR_NOT_SAME_DEVICE on Windows but EEXIST elsewhere.
	if got := isCrossDevice(&os.LinkError{Err: syscall.Errno(17)}); got != (os.PathSeparator == '\\') {
		t.Fatalf("errno 17 cross-device = %v on this OS", got)
	}
}

// A dangling symlink at the original path occupies the name: restore must
// keep both (auto-rename) and leave the symlink untouched.
func TestTrash_RestoreKeepsDanglingSymlinkAtOriginalPath(t *testing.T) {
	if os.PathSeparator == '\\' {
		t.Skip("symlinks need privileges on Windows")
	}
	ops, root, trashDir := setupTrash(t)
	src := filepath.Join(root, "note.txt")
	if err := os.WriteFile(src, []byte("v1"), 0o644); err != nil {
		t.Fatal(err)
	}
	if res := ops.MoveToTrash([]string{src}, trashDir); !res[0].OK {
		t.Fatalf("trash failed: %+v", res)
	}
	if err := os.Symlink("missing-target", src); err != nil {
		t.Fatal(err)
	}
	items, _ := ListTrash(trashDir)
	rr := ops.RestoreFromTrash([]string{items[0].ID}, trashDir)
	if !rr[0].OK {
		t.Fatalf("restore failed: %+v (%+v)", rr, rr[0].Error)
	}
	if rr[0].Path == src {
		t.Fatalf("restore replaced the dangling symlink instead of keeping both")
	}
	if fi, err := os.Lstat(src); err != nil || fi.Mode()&os.ModeSymlink == 0 {
		t.Fatalf("dangling symlink was clobbered: %v %v", fi, err)
	}
	if got, _ := os.ReadFile(rr[0].Path); string(got) != "v1" {
		t.Fatalf("restored copy = %q, want v1", got)
	}
}

// Same-basename files trashed concurrently must each get their own entry; the
// name pick and the rename are one critical section.
func TestTrash_ConcurrentSameBasenameDistinctEntries(t *testing.T) {
	ops, root, trashDir := setupTrash(t)
	const n = 24
	paths := make([]string, n)
	for i := range paths {
		dir := filepath.Join(root, fmt.Sprintf("d%d", i))
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		paths[i] = filepath.Join(dir, "same.txt")
		if err := os.WriteFile(paths[i], []byte(fmt.Sprintf("content-%d", i)), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	start := make(chan struct{})
	var wg sync.WaitGroup
	oks := make([]bool, n)
	for i := range paths {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			res := ops.MoveToTrash([]string{paths[i]}, trashDir)
			oks[i] = res[0].OK
		}()
	}
	close(start)
	wg.Wait()
	for i, ok := range oks {
		if !ok {
			t.Fatalf("trash %d failed", i)
		}
	}
	items, err := ListTrash(trashDir)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != n {
		t.Fatalf("got %d trash entries, want %d (entries overwrote each other)", len(items), n)
	}
	seen := map[string]bool{}
	for _, it := range items {
		b, err := os.ReadFile(filepath.Join(trashFilesDir(trashDir), it.ID))
		if err != nil {
			t.Fatal(err)
		}
		seen[string(b)] = true
	}
	if len(seen) != n {
		t.Fatalf("got %d distinct payloads, want %d", len(seen), n)
	}
}

// If the sidecar write fails and the rollback fails too, the error must say the
// item is stranded and where, instead of silently losing track of it.
func TestTrash_RollbackFailureIsReported(t *testing.T) {
	if os.Geteuid() == 0 || os.PathSeparator == '\\' {
		t.Skip("needs permission bits to be enforced")
	}
	ops, root, trashDir := setupTrash(t)
	dir := filepath.Join(root, "sub")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	src := filepath.Join(dir, "keep.txt")
	if err := os.WriteFile(src, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	orig := writeTrashInfoFn
	t.Cleanup(func() {
		writeTrashInfoFn = orig
		_ = os.Chmod(dir, 0o755)
	})
	writeTrashInfoFn = func(string, string, string) error {
		// The payload is already in the store; make the original parent
		// read-only so moving it back fails.
		if err := os.Chmod(dir, 0o555); err != nil {
			t.Fatal(err)
		}
		return errors.New("sidecar write failed")
	}
	res := ops.MoveToTrash([]string{src}, trashDir)
	if res[0].OK || res[0].Error == nil {
		t.Fatalf("expected failure, got %+v", res[0])
	}
	msg := res[0].Error.Message
	stranded := filepath.Join(trashFilesDir(trashDir), "keep.txt")
	if !strings.Contains(msg, "sidecar write failed") || !strings.Contains(msg, "stranded") || !strings.Contains(msg, stranded) {
		t.Fatalf("error does not name the stranded path: %q", msg)
	}
	if _, err := os.Stat(stranded); err != nil {
		t.Fatalf("payload should be stranded at %s: %v", stranded, err)
	}
}

// A directory must not be renamed onto an existing (empty) directory: os.Rename refused that, and so must the
// descriptor-relative rename used for jailed paths.
func TestRenameAcrossRoots_RefusesExistingTarget(t *testing.T) {
	ops, root, trashDir := setupTrash(t)
	if err := os.MkdirAll(filepath.Join(root, "d"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(trashFilesDir(trashDir), "d"), 0o755); err != nil {
		t.Fatal(err)
	}
	src, err := ops.access(filepath.Join(root, "d"))
	if err != nil {
		t.Fatal(err)
	}
	defer src.close()
	dst := &securePath{full: filepath.Join(trashFilesDir(trashDir), "d")}
	if err := renameAcrossRoots(src, dst); err == nil {
		t.Fatal("rename onto an existing directory must fail")
	}
	if _, err := os.Stat(filepath.Join(root, "d")); err != nil {
		t.Fatalf("source disappeared: %v", err)
	}
}
