package server

import (
	"container/heap"
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"sort"
	"testing"
	"time"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/fsops"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/sidecar"
)

// indexdBinary locates a built rfe-indexd for the differential tests; they skip when there is none
// (build one with `cargo build --release -p rfe-indexd` in agent-rs, or set RFE_SIDECAR_DIR).
func indexdBinary(t *testing.T) string {
	t.Helper()
	if loc, ok, _ := locateSidecar("rfe-indexd"); ok {
		return loc.path
	}
	name := "rfe-indexd"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	for _, sub := range []string{"release", "debug"} {
		p := filepath.Join("..", "..", "..", "agent-rs", "target", sub, name)
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	t.Skip("rfe-indexd is not built")
	return ""
}

// diffFixture lays out a tree that exercises the walk rules: hidden and pruned directories, hidden files,
// absolute and relative symlinks, links to directories, broken links, links leaving the root.
func diffFixture(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	base := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
	n := 0
	put := func(rel string, size int) {
		p := filepath.Join(root, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, make([]byte, size), 0o644); err != nil {
			t.Fatal(err)
		}
		n++
		mt := base.Add(time.Duration(n) * time.Hour)
		if err := os.Chtimes(p, mt, mt); err != nil {
			t.Fatal(err)
		}
	}
	for _, f := range []struct {
		rel  string
		size int
	}{
		{"photo.jpg", 1000}, {"Photo.PNG", 2000}, {"movie.mp4", 5000}, {"song.mp3", 500}, {"notes.txt", 10},
		{"archive.zip", 3000}, {"weird.xyz", 100}, {"noext", 7}, {".hidden-file", 3},
		{"a/b/c/deep.txt", 42}, {"a/b/photo2.jpg", 1200}, {"a/Zed.TXT", 9}, {"a/alpha.txt", 11},
		{"docs/readme.md", 300}, {"docs/spec.pdf", 90000}, {"docs/UPPER.DOC", 120},
		{".git/config", 5}, {"node_modules/pkg/index.js", 77}, {"a/.cache/x.bin", 8}, {"café/naïve.txt", 13},
		{"sp ace/file name.txt", 14}, {"unicode/日本語.txt", 15},
	} {
		put(f.rel, f.size)
	}
	outside := t.TempDir()
	if err := os.WriteFile(filepath.Join(outside, "secret.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	links := map[string]string{
		"link-abs-dir":     filepath.Join(root, "docs"),
		"link-rel-dir":     "docs",
		"link-abs-file":    filepath.Join(root, "photo.jpg"),
		"link-rel-file":    "a/alpha.txt",
		"link-broken":      "does-not-exist",
		"link-outside":     outside,
		"link-outside-fil": filepath.Join(outside, "secret.txt"),
		"a/link-up":        "../docs",
	}
	names := make([]string, 0, len(links))
	for name := range links {
		names = append(names, name)
	}
	sort.Strings(names)
	for i, name := range names {
		p := filepath.Join(root, filepath.FromSlash(name))
		if err := os.Symlink(links[name], p); err != nil {
			t.Skipf("symlinks unavailable: %v", err)
		}
		// Distinct mtimes: ties would make the order of equal entries differ between implementations.
		if err := setLinkTime(p, base.Add(time.Duration(100+i)*time.Hour)); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func diffQuery(t *testing.T, raw string) *searchFilters {
	t.Helper()
	q, err := url.ParseQuery(raw)
	if err != nil {
		t.Fatal(err)
	}
	f, code, msg := parseSearchFilters(q)
	if code != "" {
		t.Fatalf("%s: %s %s", raw, code, msg)
	}
	return f
}

func entryKey(e fsops.Entry) map[string]any {
	return map[string]any{
		"name": e.Name, "path": e.Path, "isDir": e.IsDir, "size": e.Size, "mime": e.MimeType, "mode": e.Mode,
		"mod": e.Modified.UnixNano(), "created": e.Created.UnixNano(), "isSymlink": e.IsSymlink, "target": e.SymlinkTarget,
	}
}

func keys(es []fsops.Entry) []map[string]any {
	out := make([]map[string]any, len(es))
	for i, e := range es {
		out[i] = entryKey(e)
	}
	return out
}

func TestSidecarIndexMatchesGoIndex(t *testing.T) {
	bin := indexdBinary(t)
	root := diffFixture(t)
	ops := fsops.New([]string{root}, false)

	goIdx := &SearchIndex{ops: ops}
	goIdx.rebuild()

	si := newSidecarIndex(ops, sidecar.Config{Name: "rfe-indexd", Path: bin, Logf: t.Logf})
	t.Cleanup(si.sup.Stop)
	deadline := time.Now().Add(10 * time.Second)
	for {
		if _, _, ok := si.query(diffQuery(t, "q=photo"), []string{root}, 10); ok {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("sidecar index never became ready")
		}
		time.Sleep(20 * time.Millisecond)
	}

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
	limits := []int{1000, 3}
	for _, raw := range queries {
		for _, rs := range rootSets {
			for _, limit := range limits {
				f := diffQuery(t, raw)
				want, wantTrunc, wantOK := goIdx.query(f, rs, limit)
				got, gotTrunc, gotOK := si.query(f, rs, limit)
				if !wantOK || !gotOK {
					t.Fatalf("%s roots=%v: ok go=%v sidecar=%v", raw, rs, wantOK, gotOK)
				}
				if !reflect.DeepEqual(keys(got), keys(want)) || gotTrunc != wantTrunc {
					t.Errorf("%s roots=%v limit=%d trunc go=%v sidecar=%v: %s", raw, rs, limit, wantTrunc, gotTrunc, firstDiff(want, got))
				}
			}
		}
	}
}

func firstDiff(want, got []fsops.Entry) string {
	if len(want) != len(got) {
		return fmt.Sprintf("count go=%d sidecar=%d\n go      %v\n sidecar %v", len(want), len(got), paths(want), paths(got))
	}
	for i := range want {
		a, b := entryKey(want[i]), entryKey(got[i])
		for k := range a {
			if !reflect.DeepEqual(a[k], b[k]) {
				return fmt.Sprintf("%s field %s: go=%v sidecar=%v", want[i].Path, k, a[k], b[k])
			}
		}
	}
	return "equal"
}

func paths(es []fsops.Entry) []string {
	out := make([]string, len(es))
	for i, e := range es {
		out[i] = e.Path
	}
	return out
}

func TestSidecarRecentsMatchGoWalk(t *testing.T) {
	bin := indexdBinary(t)
	root := diffFixture(t)
	ops := fsops.New([]string{root}, false)
	sup := sidecar.NewSupervisor(sidecar.Config{Name: "rfe-indexd", Path: bin, Logf: t.Logf}, nil)
	sup.Run()
	t.Cleanup(sup.Stop)
	deadline := time.Now().Add(10 * time.Second)
	for {
		if _, err := sup.Client(); err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("sidecar never started")
		}
		time.Sleep(20 * time.Millisecond)
	}
	walk := sidecarRecentWalker(sup)
	for _, limit := range []int{1, 5, 8, 100} {
		for _, r := range []string{root, filepath.Join(root, "a"), filepath.Join(root, "docs")} {
			var want, got recentHeap
			heap.Init(&want)
			heap.Init(&got)
			walkForRecentWithOps(context.Background(), ops, r, limit, &want)
			walk(context.Background(), ops, r, limit, &got)
			if !reflect.DeepEqual(keys(got.sortedNewestFirst()), keys(want.sortedNewestFirst())) {
				t.Errorf("limit %d root %s: %s", limit, r, firstDiff(want.sortedNewestFirst(), got.sortedNewestFirst()))
			}
		}
	}
}

func TestSidecarFallsBackWhenUnavailable(t *testing.T) {
	ops := fsops.New([]string{t.TempDir()}, false)
	si := newSidecarIndex(ops, sidecar.Config{Name: "rfe-indexd", Path: "/nonexistent/rfe-indexd"})
	t.Cleanup(si.sup.Stop)
	if _, _, ok := si.query(diffQuery(t, "q=x"), ops.Roots(), 10); ok {
		t.Fatal("query reported ok with no sidecar")
	}
	// The recents walker must still produce the Go walk's result.
	dir := ops.Roots()[0]
	if err := os.WriteFile(filepath.Join(dir, "f.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	var h recentHeap
	heap.Init(&h)
	sidecarRecentWalker(si.sup)(context.Background(), ops, dir, 5, &h)
	if h.Len() != 1 {
		t.Fatalf("fallback walk found %d entries, want 1", h.Len())
	}
}

func TestAcceptSidecarPath(t *testing.T) {
	root := filepath.FromSlash("/srv/data")
	scopes := prepareRootScopes([]string{root})
	if runtime.GOOS == "windows" {
		t.Skip("POSIX paths")
	}
	for p, want := range map[string]bool{
		"/srv/data":                true,
		"/srv/data/a.txt":          true,
		"/srv/data/a/../../etc/pw": false,
		"/srv/data/./a":            false,
		"/srv/data//a":             false,
		"/srv/data-evil/a":         false,
		"/srv/dat":                 false,
		"srv/data/a":               false,
		"":                         false,
		"/etc/passwd":              false,
	} {
		if got := acceptSidecarPath(p, scopes); got != want {
			t.Errorf("%q: got %v want %v", p, got, want)
		}
	}
}

func TestSearchSurvivesSidecarKilledMidFlight(t *testing.T) {
	bin := indexdBinary(t)
	root := diffFixture(t)
	ops := fsops.New([]string{root}, false)
	si := newSidecarIndex(ops, sidecar.Config{Name: "rfe-indexd", Path: bin, Logf: t.Logf})
	t.Cleanup(si.sup.Stop)

	search := func() []fsops.Entry {
		rr := httptest.NewRecorder()
		req := httptest.NewRequest("GET", "/v1/search?q=photo", nil)
		searchHandler(ops, si)(rr, req)
		if rr.Code != 200 {
			t.Fatalf("status %d: %s", rr.Code, rr.Body.String())
		}
		var out []fsops.Entry
		if err := json.Unmarshal(rr.Body.Bytes(), &out); err != nil {
			t.Fatal(err)
		}
		return out
	}
	waitFor := func(what string, cond func() bool) {
		t.Helper()
		deadline := time.Now().Add(15 * time.Second)
		for !cond() {
			if time.Now().After(deadline) {
				t.Fatalf("timed out waiting for %s", what)
			}
			time.Sleep(10 * time.Millisecond)
		}
	}
	waitFor("the first snapshot", func() bool {
		_, _, ok := si.query(diffQuery(t, "q=photo"), []string{root}, 10)
		return ok
	})
	want := paths(search())
	if len(want) == 0 {
		t.Fatal("no results from the sidecar index")
	}

	c, err := si.sup.Client()
	if err != nil {
		t.Fatal(err)
	}
	p, err := os.FindProcess(c.Pid())
	if err != nil {
		t.Fatal(err)
	}
	// Searches keep arriving while the process dies: none may fail or come back different.
	stop := make(chan struct{})
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			select {
			case <-stop:
				return
			default:
			}
			if got := paths(search()); !reflect.DeepEqual(got, want) {
				t.Errorf("search during the kill returned %v, want %v", got, want)
				return
			}
		}
	}()
	time.Sleep(30 * time.Millisecond)
	_ = p.Kill()
	waitFor("the sidecar to be noticed dead", func() bool { _, err := si.sup.Client(); return err != nil })
	waitFor("the supervisor to restart it and rebuild", func() bool {
		_, _, ok := si.query(diffQuery(t, "q=photo"), []string{root}, 10)
		return ok
	})
	close(stop)
	<-done
	if got := paths(search()); !reflect.DeepEqual(got, want) {
		t.Fatalf("after the restart got %v, want %v", got, want)
	}
}

func TestSidecarIndexSeesChangesWithoutARebuild(t *testing.T) {
	bin := indexdBinary(t)
	root := diffFixture(t)
	ops := fsops.New([]string{root}, false)
	si := newSidecarIndex(ops, sidecar.Config{Name: "rfe-indexd", Path: bin, Logf: t.Logf})
	t.Cleanup(si.sup.Stop)
	has := func(name string) bool {
		got, _, ok := si.query(diffQuery(t, "q="+name), []string{root}, 10)
		return ok && len(got) > 0
	}
	deadline := time.Now().Add(15 * time.Second)
	for !has("photo") {
		if time.Now().After(deadline) {
			t.Fatal("index never ready")
		}
		time.Sleep(20 * time.Millisecond)
	}
	c := mustClient(t, si)
	if _, ok := watching(c); !ok {
		t.Skip("file system watches are unavailable here")
	}
	if err := os.WriteFile(filepath.Join(root, "a", "zz-live-added.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	for !has("zz-live-added") {
		if time.Now().After(deadline) {
			t.Fatal("a file created after the build never showed up")
		}
		time.Sleep(50 * time.Millisecond)
	}
	if err := os.Remove(filepath.Join(root, "a", "zz-live-added.txt")); err != nil {
		t.Fatal(err)
	}
	for has("zz-live-added") {
		if time.Now().After(deadline) {
			t.Fatal("a deleted file never went away")
		}
		time.Sleep(50 * time.Millisecond)
	}
}
