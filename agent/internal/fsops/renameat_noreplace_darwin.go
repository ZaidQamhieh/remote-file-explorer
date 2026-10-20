//go:build darwin

package fsops

import "golang.org/x/sys/unix"

// renameNoReplace renames atomically and fails with EEXIST if the target appeared (audit F-148).
func renameNoReplace(sfd int, sbase string, dfd int, dbase string) error {
	err := unix.RenameatxNp(sfd, sbase, dfd, dbase, unix.RENAME_EXCL)
	if err == unix.ENOTSUP || err == unix.EINVAL {
		return unix.Renameat(sfd, sbase, dfd, dbase)
	}
	return err
}
