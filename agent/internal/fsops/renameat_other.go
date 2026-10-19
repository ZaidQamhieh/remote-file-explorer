//go:build !linux && !darwin

package fsops

import (
	"fmt"
	"os"
	"path/filepath"
)

// renameAcrossRoots renames src to dst when at most one side is jailed. There
// is no descriptor-relative rename here, so it renames by absolute path. That
// follows symlinks in the parents, so first check that the jailed side's parent
// is still its own canonical path and that the jail root itself is not being
// moved.
func renameAcrossRoots(src, dst *securePath) error {
	for _, side := range []*securePath{src, dst} {
		if side.root == nil {
			continue
		}
		if side.name == "." {
			return fmt.Errorf("cannot move the jail root")
		}
		parent := filepath.Dir(side.full)
		if real, rerr := filepath.EvalSymlinks(parent); rerr != nil || real != parent {
			return fmt.Errorf("path changed during the operation")
		}
	}
	return os.Rename(src.full, dst.full)
}
