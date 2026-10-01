package thumbs

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/sidecar"
)

type crashingRemote struct {
	err   error
	calls int
}

func (c *crashingRemote) Render(context.Context, []byte, int) ([]byte, error) {
	c.calls++
	return nil, c.err
}

// A sidecar that dies while it holds a file must not push that file into the unsandboxed in-process decoder, even
// though the built-in decoder could handle it: the first interruption is transient, the second poisons the file.
func TestInterruptedSidecarNeverFallsBackToInProcessDecode(t *testing.T) {
	src, err := os.ReadFile(filepath.Join(fixtureDir, "photo.jpg"))
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "p.jpg")
	if err := os.WriteFile(path, src, 0o644); err != nil {
		t.Fatal(err)
	}
	remote := &crashingRemote{err: fmt.Errorf("%w: %w: process exited", sidecar.ErrUnavailable, sidecar.ErrInterrupted)}
	rn, err := New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	rn.UseRemote(remote)

	_, err = rn.Get(path, 96)
	if err == nil || errors.Is(err, ErrNotSupported) {
		t.Fatalf("first interruption: err = %v, want a transient error that is not ErrNotSupported", err)
	}
	_, err = rn.Get(path, 96)
	if !errors.Is(err, ErrNotSupported) {
		t.Fatalf("second interruption: err = %v, want ErrNotSupported", err)
	}
	calls := remote.calls
	if _, err = rn.Get(path, 96); !errors.Is(err, ErrNotSupported) || remote.calls != calls {
		t.Fatalf("poisoned file: err = %v, remote calls %d -> %d (must not call the sidecar again)", err, calls, remote.calls)
	}

	// A different version of the same file gets a fresh chance (and here still cannot be decoded in-process).
	time.Sleep(10 * time.Millisecond)
	if err := os.WriteFile(path, append(src, 0), 0o644); err != nil {
		t.Fatal(err)
	}
	future := time.Now().Add(time.Hour)
	_ = os.Chtimes(path, future, future)
	if _, err = rn.Get(path, 96); err == nil || errors.Is(err, ErrNotSupported) {
		t.Fatalf("changed file: err = %v, want a transient error again", err)
	}
}

// A sidecar that was simply not running (no interruption) still falls back to the built-in decoder.
func TestUnavailableSidecarStillFallsBack(t *testing.T) {
	path := filepath.Join(fixtureDir, "photo.jpg")
	rn, err := New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	rn.UseRemote(&crashingRemote{err: sidecar.ErrUnavailable})
	if data, err := rn.Get(path, 96); err != nil || len(data) == 0 {
		t.Fatalf("fallback render: %v", err)
	}
}

func TestCrashLogIsBounded(t *testing.T) {
	var l crashLog
	for i := 0; i < crashLogCap*2; i++ {
		l.strike(crashKey{path: fmt.Sprint(i)})
	}
	if len(l.strikes) > crashLogCap {
		t.Fatalf("crash log holds %d entries, cap %d", len(l.strikes), crashLogCap)
	}
}
