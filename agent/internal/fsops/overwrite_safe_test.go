//go:build unix

package fsops

import (
	"os"
	"path/filepath"
	"syscall"
	"testing"
)

// F-41/F-120: an overwrite that fails part-way must leave the old destination in place.
func TestCopyOverwrite_FailedCopyKeepsDestination(t *testing.T) {
	ops, root := setupJail(t)
	src := filepath.Join(root, "src", "item")
	dstDir := filepath.Join(root, "dst")
	if err := os.MkdirAll(src, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dstDir, "item"), 0o755); err != nil {
		t.Fatal(err)
	}
	keep := filepath.Join(dstDir, "item", "old.txt")
	if err := os.WriteFile(keep, []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(src, "a.txt"), []byte("new"), 0o644); err != nil {
		t.Fatal(err)
	}
	// A FIFO inside the source makes the copy fail after it has started.
	if err := syscall.Mkfifo(filepath.Join(src, "zz-pipe"), 0o644); err != nil {
		t.Skip("mkfifo unavailable")
	}
	res := ops.Copy([]string{src}, dstDir, false, true)
	if res[0].OK {
		t.Fatalf("copy of a tree holding a FIFO should fail: %+v", res[0])
	}
	if b, err := os.ReadFile(keep); err != nil || string(b) != "old" {
		t.Fatalf("destination lost after a failed overwrite: %v %q", err, b)
	}
	ents, _ := os.ReadDir(dstDir)
	if len(ents) != 1 {
		t.Fatalf("leftover aside/partial entries: %v", ents)
	}
}

func TestCopyOverwrite_SuccessReplacesAndCleansUp(t *testing.T) {
	ops, root := setupJail(t)
	src := filepath.Join(root, "s.txt")
	dstDir := filepath.Join(root, "d")
	_ = os.MkdirAll(dstDir, 0o755)
	_ = os.WriteFile(src, []byte("new"), 0o644)
	_ = os.WriteFile(filepath.Join(dstDir, "s.txt"), []byte("old"), 0o644)
	res := ops.Copy([]string{src}, dstDir, false, true)
	if !res[0].OK {
		t.Fatalf("copy: %+v", res[0])
	}
	if b, _ := os.ReadFile(filepath.Join(dstDir, "s.txt")); string(b) != "new" {
		t.Fatalf("not replaced: %q", b)
	}
	if ents, _ := os.ReadDir(dstDir); len(ents) != 1 {
		t.Fatalf("aside copy left behind: %v", ents)
	}
}
