//go:build linux

package fsops

import "golang.org/x/sys/unix"

// renameNoReplace renames atomically and fails with EEXIST if the target appeared, instead of replacing it
// (audit F-148). A file system without RENAME_NOREPLACE falls back to the checked rename.
func renameNoReplace(sfd int, sbase string, dfd int, dbase string) error {
	err := unix.Renameat2(sfd, sbase, dfd, dbase, unix.RENAME_NOREPLACE)
	if err == unix.EINVAL || err == unix.ENOSYS {
		return unix.Renameat(sfd, sbase, dfd, dbase)
	}
	return err
}
