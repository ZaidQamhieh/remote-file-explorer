package thumbs

import (
	"bytes"
	"encoding/binary"
	"errors"
	"hash/crc32"
	"os"
	"path/filepath"
	"testing"
)

func TestRenderRejectsOversizedSourceFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "huge.png")
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.Truncate(maxSourceBytes + 1); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := Render(path, 256); !errors.Is(err, ErrResourceLimit) {
		t.Fatalf("expected ErrResourceLimit, got %v", err)
	}
}

func TestRenderRejectsExcessivePixelCountBeforeDecode(t *testing.T) {
	path := filepath.Join(t.TempDir(), "huge.png")
	if err := os.WriteFile(path, minimalPNG(100_000, 100_000), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Render(path, 256); !errors.Is(err, ErrResourceLimit) {
		t.Fatalf("expected ErrResourceLimit, got %v", err)
	}
}

func minimalPNG(width, height uint32) []byte {
	var out bytes.Buffer
	out.Write([]byte("\x89PNG\r\n\x1a\n"))
	ihdr := make([]byte, 13)
	binary.BigEndian.PutUint32(ihdr[0:4], width)
	binary.BigEndian.PutUint32(ihdr[4:8], height)
	ihdr[8] = 8 // bit depth
	ihdr[9] = 2 // truecolor
	writePNGChunk(&out, "IHDR", ihdr)
	writePNGChunk(&out, "IEND", nil)
	return out.Bytes()
}

func writePNGChunk(out *bytes.Buffer, typ string, data []byte) {
	_ = binary.Write(out, binary.BigEndian, uint32(len(data)))
	out.WriteString(typ)
	out.Write(data)
	crc := crc32.NewIEEE()
	_, _ = crc.Write([]byte(typ))
	_, _ = crc.Write(data)
	_ = binary.Write(out, binary.BigEndian, crc.Sum32())
}
