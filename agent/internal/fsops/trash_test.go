package fsops

import (
	"os"
	"path/filepath"
	"testing"
)

// setupTrash returns an Ops jailed to a temp root plus a separate trash dir.
func setupTrash(t *testing.T) (ops *Ops, root, trashDir string) {
	t.Helper()
	ops, root = setupJail(t)
	trashDir = filepath.Join(t.TempDir(), "Trash")
	return ops, root, trashDir
}

// TestTrash_MoveListRestore covers the full lifecycle: a file moves to trash
// (gone from its original location, present in the store + listing), then
// restores back to where it came from.
func TestTrash_MoveListRestore(t *testing.T) {
	ops, root, trashDir := setupTrash(t)
	src := filepath.Join(root, "doc.txt")
	if err := os.WriteFile(src, []byte("keep me"), 0o644); err != nil {
		t.Fatal(err)
	}

	res := ops.MoveToTrash([]string{src}, trashDir)
	if len(res) != 1 || !res[0].OK {
		t.Fatalf("MoveToTrash: %+v", res)
	}
	if _, err := os.Stat(src); !os.IsNotExist(err) {
		t.Fatalf("original still present after trashing")
	}

	items, err := ListTrash(trashDir)
	if err != nil {
		t.Fatalf("ListTrash: %v", err)
	}
	if len(items) != 1 || items[0].OriginalPath != src || items[0].Name != "doc.txt" {
		t.Fatalf("unexpected trash listing: %+v", items)
	}

	rr := ops.RestoreFromTrash([]string{items[0].ID}, trashDir)
	if len(rr) != 1 || !rr[0].OK {
		t.Fatalf("RestoreFromTrash: %+v", rr)
	}
	if got, _ := os.ReadFile(src); string(got) != "keep me" {
		t.Fatalf("restored content = %q, want 'keep me'", got)
	}
	// Trash is now empty.
	if items, _ := ListTrash(trashDir); len(items) != 0 {
		t.Fatalf("trash not empty after restore: %+v", items)
	}
}

// TestTrash_RestoreAutoRenamesOnCollision verifies a restore doesn't clobber a
// file that reappeared at the original path.
func TestTrash_RestoreAutoRenamesOnCollision(t *testing.T) {
	ops, root, trashDir := setupTrash(t)
	src := filepath.Join(root, "note.txt")
	if err := os.WriteFile(src, []byte("v1"), 0o644); err != nil {
		t.Fatal(err)
	}
	ops.MoveToTrash([]string{src}, trashDir)
	// A new file takes the original name before we restore.
	if err := os.WriteFile(src, []byte("v2"), 0o644); err != nil {
		t.Fatal(err)
	}

	items, _ := ListTrash(trashDir)
	rr := ops.RestoreFromTrash([]string{items[0].ID}, trashDir)
	if !rr[0].OK {
		t.Fatalf("restore failed: %+v", rr)
	}
	if rr[0].Path == src {
		t.Fatalf("restore clobbered the occupant instead of auto-renaming")
	}
	if got, _ := os.ReadFile(src); string(got) != "v2" {
		t.Fatalf("occupant was overwritten: %q", got)
	}
	if got, _ := os.ReadFile(rr[0].Path); string(got) != "v1" {
		t.Fatalf("restored copy = %q, want v1", got)
	}
}

// TestTrash_Empty removes everything from the store.
func TestTrash_Empty(t *testing.T) {
	ops, root, trashDir := setupTrash(t)
	for _, n := range []string{"a.txt", "b.txt"} {
		p := filepath.Join(root, n)
		if err := os.WriteFile(p, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
		ops.MoveToTrash([]string{p}, trashDir)
	}
	if items, _ := ListTrash(trashDir); len(items) != 2 {
		t.Fatalf("expected 2 trashed items, got %d", len(items))
	}
	if err := EmptyTrash(trashDir, nil); err != nil {
		t.Fatalf("EmptyTrash: %v", err)
	}
	if items, _ := ListTrash(trashDir); len(items) != 0 {
		t.Fatalf("trash not empty: %+v", items)
	}
}

// TestTrash_ReadOnly verifies trashing is blocked in read-only mode.
func TestTrash_ReadOnly(t *testing.T) {
	root := t.TempDir()
	ro := New([]string{root}, true)
	src := filepath.Join(root, "x.txt")
	if err := os.WriteFile(src, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	res := ro.MoveToTrash([]string{src}, filepath.Join(t.TempDir(), "Trash"))
	if res[0].OK || res[0].Error == nil || res[0].Error.Code != "READ_ONLY" {
		t.Fatalf("expected READ_ONLY, got %+v", res[0])
	}
}

// TestTrash_MoveOutsideJail verifies a path outside the jail can't be trashed.
func TestTrash_MoveOutsideJail(t *testing.T) {
	ops, _, trashDir := setupTrash(t)
	outside := filepath.Join(t.TempDir(), "secret.txt")
	if err := os.WriteFile(outside, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	res := ops.MoveToTrash([]string{outside}, trashDir)
	if res[0].OK || res[0].Error == nil || res[0].Error.Code != "FORBIDDEN" {
		t.Fatalf("expected FORBIDDEN, got %+v", res[0])
	}
}
