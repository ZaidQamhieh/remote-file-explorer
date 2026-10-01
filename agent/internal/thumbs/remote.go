package thumbs

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"sync"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/sidecar"
)

// Remote renders a thumbnail somewhere else (the rfe-thumbd sidecar). The returned errors tell the renderer what
// to do next: errRemoteUnsupported means "this process cannot decode it, try the built-in decoder", ErrNotSupported
// means "nobody can", and anything else is a sidecar failure that also falls back to the built-in decoder.
type Remote interface {
	Render(ctx context.Context, source []byte, maxSize int) ([]byte, error)
}

var errRemoteUnsupported = errors.New("remote renderer cannot decode this source")

// UseRemote makes the renderer try r before its own decoder. It must be called before the renderer is shared.
func (rn *Renderer) UseRemote(r Remote) { rn.remote = r }

// SidecarRemote adapts a supervised rfe-thumbd to Remote.
type SidecarRemote struct{ Sup *sidecar.Supervisor }

type renderResp struct {
	Width  int    `json:"width"`
	Height int    `json:"height"`
	Format string `json:"format"`
}

func (r SidecarRemote) Render(ctx context.Context, source []byte, maxSize int) ([]byte, error) {
	var resp renderResp
	jpeg, err := r.Sup.CallBody(ctx, "thumb.render", map[string]int{"maxSize": maxSize}, source, &resp)
	if err != nil {
		var re *sidecar.RemoteError
		if errors.As(err, &re) {
			switch re.Code {
			case "NOT_SUPPORTED":
				return nil, errRemoteUnsupported
			case "TOO_LARGE":
				return nil, fmt.Errorf("%w: %s", ErrNotSupported, re.Message)
			}
		}
		return nil, err
	}
	if len(jpeg) < 4 || jpeg[0] != 0xff || jpeg[1] != 0xd8 {
		return nil, errors.New("sidecar returned something that is not a JPEG")
	}
	return jpeg, nil
}

// renderWithRemote tries the remote renderer and reports whether it produced the result (or a final error). When
// it did not (unsupported format, sidecar down or misbehaving), the caller uses the built-in decoder.
func (rn *Renderer) renderWithRemote(ctx context.Context, f *os.File, size int64, maxSize int) (data []byte, final bool, err error) {
	if rn.remote == nil || size <= 0 || size > maxThumbSourceBytes {
		return nil, false, nil
	}
	release, err := acquireDecodeSlot(ctx, fullDecodeSem)
	if err != nil {
		return nil, true, err
	}
	defer release()
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		return nil, true, err
	}
	src, err := io.ReadAll(io.LimitReader(f, maxThumbSourceBytes+1))
	if err != nil {
		return nil, true, err
	}
	if int64(len(src)) > maxThumbSourceBytes {
		return nil, false, nil // grew while reading; the built-in path applies its own cap
	}
	key, haveKey := crashKeyOf(f)
	if haveKey && rn.crashes.poisoned(key) {
		return nil, true, fmt.Errorf("%w: the thumbnail sidecar crashed on this file before", ErrNotSupported)
	}
	data, err = rn.remote.Render(ctx, src, maxSize)
	switch {
	case err == nil:
		return data, true, nil
	case ctx.Err() != nil:
		return nil, true, ctx.Err()
	case errors.Is(err, ErrNotSupported):
		return nil, true, err
	case errors.Is(err, errRemoteUnsupported):
		sidecar.Note("thumbd.unsupported-format") // expected: the built-in decoder handles it
		return nil, false, nil
	case errors.Is(err, sidecar.ErrInterrupted):
		sidecar.Note("thumbd.interrupted")
		// The sidecar died while it held this file. Decoding it here would run the very input that may have just
		// killed the sandboxed decoder inside the unsandboxed agent, so it is not retried in-process. The first
		// strike is a transient error (the phone retries on the restarted sidecar); a second on the same file
		// marks it as one the sidecar cannot survive.
		if haveKey && rn.crashes.strike(key) {
			sidecar.Note("thumbd.poisoned-file")
			return nil, true, fmt.Errorf("%w: the thumbnail sidecar crashed on this file twice", ErrNotSupported)
		}
		return nil, true, fmt.Errorf("thumbnail sidecar was interrupted: %w", err)
	default:
		// Not running, refused or misbehaving: this render ran in-process instead.
		sidecar.Note("thumbd.fallback")
		return nil, false, nil
	}
}

// crashKey identifies a file version: a changed file gets a fresh chance.
type crashKey struct {
	path string
	size int64
	mod  int64
}

func crashKeyOf(f *os.File) (crashKey, bool) {
	st, err := f.Stat()
	if err != nil {
		return crashKey{}, false
	}
	return crashKey{path: f.Name(), size: st.Size(), mod: st.ModTime().UnixNano()}, true
}

const crashLogCap = 256

// crashLog remembers (bounded, oldest out first) the files a sidecar render was interrupted on. Other renders in
// flight when the sidecar dies are interrupted too, which is why one strike does not condemn a file.
type crashLog struct {
	mu      sync.Mutex
	strikes map[crashKey]int
	order   []crashKey
}

func (l *crashLog) poisoned(k crashKey) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.strikes[k] >= 2
}

// strike records one interruption and reports whether the file is now poisoned.
func (l *crashLog) strike(k crashKey) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.strikes == nil {
		l.strikes = make(map[crashKey]int)
	}
	if _, seen := l.strikes[k]; !seen {
		l.order = append(l.order, k)
		if len(l.order) > crashLogCap {
			delete(l.strikes, l.order[0])
			l.order = l.order[1:]
		}
	}
	l.strikes[k]++
	return l.strikes[k] >= 2
}
