//go:build linux || darwin

package fsops

import (
	"fmt"
	"os"
	"path/filepath"

	"golang.org/x/sys/unix"
)

// renameAcrossRoots renames src to dst when at most one side is jailed. The
// jailed side's parent directory is opened through its os.Root (so a symlink in
// an ancestor cannot lead outside the jail, even if swapped after the jail
// check) and the rename is done with renameat on directory descriptors, which
// does not re-resolve the paths. The unjailed side is the agent-managed trash
// store, opened by path.
func renameAcrossRoots(src, dst *securePath) error {
	for _, side := range []*securePath{src, dst} {
		if side.root != nil && side.name == "." {
			return fmt.Errorf("cannot move the jail root")
		}
	}
	sdir, sbase, err := openParentDir(src)
	if err != nil {
		return &os.LinkError{Op: "rename", Old: src.full, New: dst.full, Err: err}
	}
	defer sdir.Close()
	ddir, dbase, err := openParentDir(dst)
	if err != nil {
		return &os.LinkError{Op: "rename", Old: src.full, New: dst.full, Err: err}
	}
	defer ddir.Close()

	var rerr error
	cerr := sdir.Control(func(sfd uintptr) {
		derr := ddir.Control(func(dfd uintptr) {
			// os.Rename refuses an existing directory target; renameat would replace an empty one.
			var st unix.Stat_t
			if unix.Fstatat(int(dfd), dbase, &st, unix.AT_SYMLINK_NOFOLLOW) == nil {
				rerr = unix.EEXIST
				return
			}
			rerr = renameNoReplace(int(sfd), sbase, int(dfd), dbase)
		})
		if derr != nil {
			rerr = derr
		}
	})
	if cerr != nil {
		rerr = cerr
	}
	if rerr != nil {
		return &os.LinkError{Op: "rename", Old: src.full, New: dst.full, Err: rerr}
	}
	return nil
}

// dirHandle is an open parent directory.
type dirHandle struct {
	f *os.File
}

func (d dirHandle) Close() { _ = d.f.Close() }

func (d dirHandle) Control(fn func(fd uintptr)) error {
	sc, err := d.f.SyscallConn()
	if err != nil {
		return err
	}
	return sc.Control(fn)
}

// openParentDir opens p's parent directory (through p's root when jailed) and
// returns it with p's final path element.
func openParentDir(p *securePath) (dirHandle, string, error) {
	if p.root != nil {
		f, err := p.root.Open(filepath.Dir(p.name))
		if err != nil {
			return dirHandle{}, "", err
		}
		return dirHandle{f}, filepath.Base(p.name), nil
	}
	f, err := os.Open(filepath.Dir(p.full))
	if err != nil {
		return dirHandle{}, "", err
	}
	return dirHandle{f}, filepath.Base(p.full), nil
}
