package server

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
)

// A ready sidecar index must not answer for a root it does not cover (outside the indexed roots, or under a
// pruned hidden directory); query must decline so the handler walks live. The nil supervisor makes any attempt
// to ask the sidecar fail loudly.
func TestSidecarIndexQueryDeclinesUncoveredRoot(t *testing.T) {
	root := t.TempDir()
	hidden := filepath.Join(root, ".cfg")
	if err := os.Mkdir(hidden, 0o755); err != nil {
		t.Fatal(err)
	}
	s := &sidecarIndex{ops: fsops.New([]string{root}, false)}
	for _, r := range []string{hidden, filepath.Join(hidden, "sub"), t.TempDir()} {
		if _, _, ok := s.query(&searchFilters{}, []string{r}, 10); ok {
			t.Fatalf("query(%s) ok=true, want decline", r)
		}
	}
	if !indexCovers([]string{root}, filepath.Join(root, "docs")) || !indexCovers([]string{root}, root) {
		t.Fatal("indexed root and visible subdirectory must be covered")
	}
}
