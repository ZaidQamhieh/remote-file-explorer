package server

import (
	"container/heap"
	"context"
	"encoding/json"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
)

// The Go index and the Go recents walk are the oracle for rfe-indexd. These goldens freeze what they answer for the
// differential fixture, so the Rust tests keep checking the same behaviour after the Go code is retired
// (agent-rs/crates/rfe-indexd/tests/golden_tests.rs builds the same tree from the "fixture" list and replays it).
//
// Regenerate with: RFE_UPDATE_GOLDENS=1 go test -run TestGenerateIndexGoldens ./internal/server
// TestIndexGoldensAreCurrent fails when the Go behaviour and the file drift apart.
const indexGoldenPath = "../../../agent-rs/crates/rfe-indexd/tests/data/index_golden.json"

type goldenFixtureEntry struct {
	Rel     string `json:"rel"`
	Kind    string `json:"kind"` // dir, file, link
	Size    int64  `json:"size,omitempty"`
	Target  string `json:"target,omitempty"`
	MtimeNs int64  `json:"mtimeNs"`
}

type goldenEntry struct {
	Path      string `json:"path"`
	IsDir     bool   `json:"isDir"`
	Size      int64  `json:"size"` // 0 for directories and symlinks (not reproducible across hosts)
	MtimeNs   int64  `json:"mtimeNs"`
	IsSymlink bool   `json:"isSymlink"`
	Target    string `json:"target,omitempty"`
}

type goldenQuery struct {
	Raw       string        `json:"raw"`
	Filters   wireFilters   `json:"filters"`
	Roots     []string      `json:"roots"`
	Limit     int           `json:"limit"`
	Truncated bool          `json:"truncated"`
	Entries   []goldenEntry `json:"entries"`
}

type goldenRecents struct {
	Root    string        `json:"root"`
	Limit   int           `json:"limit"`
	Entries []goldenEntry `json:"entries"`
}

type indexGolden struct {
	Note    string               `json:"note"`
	Fixture []goldenFixtureEntry `json:"fixture"`
	Queries []goldenQuery        `json:"queries"`
	Recents []goldenRecents      `json:"recents"`
}

// buildIndexGolden runs the Go implementations over the differential fixture.
func buildIndexGolden(t *testing.T) indexGolden {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("the golden fixture needs symlink timestamps")
	}
	root := diffFixture(t)
	outside := ""
	if target, err := os.Readlink(filepath.Join(root, "link-outside")); err == nil {
		outside = target
	}
	sub := func(s string) string {
		s = strings.ReplaceAll(s, root, "$ROOT")
		if outside != "" {
			s = strings.ReplaceAll(s, outside, "$OUTSIDE")
		}
		return s
	}

	// Directories get fixed mtimes (deepest first) so the tree is reproducible.
	var dirs []string
	_ = filepath.WalkDir(root, func(p string, d os.DirEntry, err error) error {
		if err == nil && d.IsDir() && p != root {
			dirs = append(dirs, p)
		}
		return nil
	})
	sort.Slice(dirs, func(i, j int) bool {
		return len(dirs[i]) > len(dirs[j]) || (len(dirs[i]) == len(dirs[j]) && dirs[i] < dirs[j])
	})
	dirTime := time.Date(2024, 2, 1, 0, 0, 0, 0, time.UTC)
	for i, d := range dirs {
		mt := dirTime.Add(time.Duration(i) * time.Hour)
		if err := os.Chtimes(d, mt, mt); err != nil {
			t.Fatal(err)
		}
	}

	g := indexGolden{Note: "generated from the Go index and Go recents walk by TestGenerateIndexGoldens; do not edit"}
	_ = filepath.WalkDir(root, func(p string, d os.DirEntry, err error) error {
		if err != nil || p == root {
			return nil
		}
		info, err := os.Lstat(p)
		if err != nil {
			t.Fatal(err)
		}
		rel, _ := filepath.Rel(root, p)
		fe := goldenFixtureEntry{Rel: filepath.ToSlash(rel), MtimeNs: info.ModTime().UnixNano()}
		switch {
		case info.Mode()&os.ModeSymlink != 0:
			fe.Kind = "link"
			target, _ := os.Readlink(p)
			fe.Target = sub(target)
		case info.IsDir():
			fe.Kind = "dir"
		default:
			fe.Kind, fe.Size = "file", info.Size()
		}
		g.Fixture = append(g.Fixture, fe)
		return nil
	})

	conv := func(es []fsops.Entry) []goldenEntry {
		out := make([]goldenEntry, len(es))
		for i, e := range es {
			size := e.Size
			if e.IsDir || e.IsSymlink {
				size = 0 // a directory's size depends on the filesystem, a link's on the length of its target path
			}
			out[i] = goldenEntry{Path: sub(e.Path), IsDir: e.IsDir, Size: size, MtimeNs: e.Modified.UnixNano(), IsSymlink: e.IsSymlink, Target: sub(e.SymlinkTarget)}
		}
		return out
	}

	ops := fsops.New([]string{root}, false)
	goIdx := &SearchIndex{ops: ops}
	goIdx.rebuild()

	queries := []string{
		"q=photo", "q=PHOTO", "q=a", "q=txt", "q=" + url.QueryEscape("*.jpg"), "q=" + url.QueryEscape("*.TXT"),
		"q=" + url.QueryEscape("p*"), "q=" + url.QueryEscape("?.txt"), "q=" + url.QueryEscape("[ab]*"),
		"q=" + url.QueryEscape("[!a-m]*"), "q=link", "q=" + url.QueryEscape("*"), "q=" + url.QueryEscape("na?ve*"),
		"q=" + url.QueryEscape("é"), "q=" + url.QueryEscape("日本"), "q=" + url.QueryEscape("file name"),
		"q=e&types=image", "q=e&types=image,video", "q=e&types=document", "q=e&types=archive,audio,other",
		"q=e&ext=jpg,png", "q=e&ext=txt", "q=e&ext=.md", "q=e&minSize=100", "q=e&maxSize=1000", "q=e&minSize=100&maxSize=2000",
		"q=e&modifiedAfter=2024-01-01T10:00:00Z", "q=e&modifiedBefore=2024-01-01T20:00:00Z",
		"q=e&modifiedAfter=2024-01-01T05:00:00Z&modifiedBefore=2024-01-01T15:00:00Z&types=image",
	}
	rootSets := [][]string{
		{root},
		{filepath.Join(root, "a")},
		{filepath.Join(root, "docs"), filepath.Join(root, "a", "b")},
		{filepath.Join(root, "a") + string(filepath.Separator)},
		{root + "-sibling"},
	}
	for _, raw := range queries {
		q, err := url.ParseQuery(raw)
		if err != nil {
			t.Fatal(err)
		}
		f, code, msg := parseSearchFilters(q)
		if code != "" {
			t.Fatalf("%s: %s %s", raw, code, msg)
		}
		for _, rs := range rootSets {
			for _, limit := range []int{1000, 3} {
				got, trunc, ok := goIdx.query(f, rs, limit)
				if !ok {
					t.Fatalf("%s: index not ready", raw)
				}
				roots := make([]string, len(rs))
				for i, r := range rs {
					roots[i] = sub(r)
				}
				g.Queries = append(g.Queries, goldenQuery{Raw: raw, Filters: toWireFilters(f), Roots: roots, Limit: limit, Truncated: trunc, Entries: conv(got)})
			}
		}
	}
	for _, limit := range []int{1, 5, 8, 100} {
		for _, r := range []string{root, filepath.Join(root, "a"), filepath.Join(root, "docs")} {
			var h recentHeap
			heap.Init(&h)
			walkForRecentWithOps(context.Background(), ops, r, limit, &h)
			g.Recents = append(g.Recents, goldenRecents{Root: sub(r), Limit: limit, Entries: conv(h.sortedNewestFirst())})
		}
	}
	return g
}

func TestGenerateIndexGoldens(t *testing.T) {
	if os.Getenv("RFE_UPDATE_GOLDENS") == "" {
		t.Skip("set RFE_UPDATE_GOLDENS=1 to regenerate")
	}
	b, err := json.MarshalIndent(buildIndexGolden(t), "", " ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(indexGoldenPath, append(b, '\n'), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestIndexGoldensAreCurrent(t *testing.T) {
	want, err := json.MarshalIndent(buildIndexGolden(t), "", " ")
	if err != nil {
		t.Fatal(err)
	}
	have, err := os.ReadFile(indexGoldenPath)
	if err != nil {
		t.Fatalf("%v (generate with RFE_UPDATE_GOLDENS=1)", err)
	}
	if strings.TrimSpace(string(have)) != strings.TrimSpace(string(want)) {
		_ = os.WriteFile(filepath.Join(os.TempDir(), "index_golden.actual.json"), append(want, '\n'), 0o644)
		t.Fatal("index_golden.json differs from what the Go index answers now; regenerate with RFE_UPDATE_GOLDENS=1 go test -run TestGenerateIndexGoldens ./internal/server and review the diff")
	}
}
