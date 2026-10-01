package thumbs

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"

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
	data, err = rn.remote.Render(ctx, src, maxSize)
	switch {
	case err == nil:
		return data, true, nil
	case ctx.Err() != nil:
		return nil, true, ctx.Err()
	case errors.Is(err, ErrNotSupported):
		return nil, true, err
	default:
		return nil, false, nil
	}
}
