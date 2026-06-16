package fsops

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// This file holds the agent's path-jail and access-control model — the
// security boundary for every filesystem operation. Resolve is the single
// chokepoint all reads and writes pass through; the SettingsView wrappers
// (read-only / per-device jail) compose the live permission state. Keeping it
// separate from the plain file CRUD in fsops.go makes the trust boundary easy
// to audit and to test in isolation (see jail_test.go / fsops_test.go).

// SettingsView supplies the live read-only flag and jail roots. fsops reads
// through it on every operation so changes apply without reconstructing Ops.
type SettingsView interface {
	IsReadOnly() bool
	Roots() []string
}

// staticSettings is an immutable SettingsView for callers (and tests) that
// pass fixed values via New.
type staticSettings struct {
	readOnly bool
	roots    []string
}

func (s staticSettings) IsReadOnly() bool { return s.readOnly }
func (s staticSettings) Roots() []string  { return s.roots }

// jailedSettings wraps a base SettingsView, overriding Roots() with a fixed
// set while delegating IsReadOnly() to the base (so live read-only toggles
// still apply to a jailed Ops).
type jailedSettings struct {
	base  SettingsView
	roots []string
}

func (s jailedSettings) IsReadOnly() bool { return s.base.IsReadOnly() }
func (s jailedSettings) Roots() []string  { return s.roots }

// roSettings forces IsReadOnly() to true while delegating Roots() to the base
// view, so a per-device read-only request reuses every existing fsops write
// guard (CreateFolder/WriteContent/Rename/Delete/…) without changing the live
// global read-only flag.
type roSettings struct{ base SettingsView }

func (s roSettings) IsReadOnly() bool { return true }
func (s roSettings) Roots() []string  { return s.base.Roots() }

// ReadOnly returns a view of o that rejects all write operations regardless of
// the live global read-only flag — used to enforce a per-device read-only flag
// (Device.ReadOnly, #8). Reads (ListDir, Meta, downloads) are unaffected. The
// returned Ops keeps o's roots and denyAll, so it composes after Jailed.
func (o *Ops) ReadOnly() *Ops {
	return &Ops{settings: roSettings{base: o.settings}, denyAll: o.denyAll}
}

// Jailed returns an Ops whose effective roots are the intersection of o's
// base roots and extraRoot (a per-device path jail, e.g. Device.JailRoot).
//
//   - If extraRoot is empty, o is returned unchanged — no per-device
//     restriction (today's behavior).
//   - If o has no configured roots (no global jail), the effective roots
//     become exactly []string{extraRoot}.
//   - If o has configured roots and extraRoot is within (or equal to) one of
//     them, the effective roots become exactly []string{extraRoot} — since
//     extraRoot is already a subset of that root, it IS the intersection.
//   - If extraRoot is outside every configured root, the returned Ops denies
//     ALL paths (a misconfigured/widening jailRoot must never grant access
//     beyond the global roots, so it is treated as "no access" rather than
//     silently falling back to the global roots).
//
// The returned Ops shares the read-only flag (live) with o but has its own
// fixed root set, so callers can safely use it for the lifetime of a single
// request.
func (o *Ops) Jailed(extraRoot string) *Ops {
	if extraRoot == "" {
		return o
	}
	clean := filepath.Clean(extraRoot)

	baseRoots := o.settings.Roots()
	if len(baseRoots) == 0 {
		// No global jail: the device's jailRoot becomes the sole root.
		return &Ops{settings: jailedSettings{base: o.settings, roots: []string{clean}}}
	}
	for _, root := range baseRoots {
		if isUnder(clean, root) {
			return &Ops{settings: jailedSettings{base: o.settings, roots: []string{clean}}}
		}
	}
	// extraRoot is outside every global root — deny everything rather than
	// widen access by falling back to the global roots.
	return &Ops{settings: jailedSettings{base: o.settings, roots: nil}, denyAll: true}
}

// Resolve cleans p and checks it against the jail.
// It also resolves symlinks to prevent symlink-escape attacks:
// if the resolved real path is outside every allowed root the request is
// rejected. When allowedRoots is empty any clean absolute path is accepted.
func (o *Ops) Resolve(p string) (string, error) {
	if o.denyAll {
		return "", fmt.Errorf("%w: %s", ErrForbidden, p)
	}
	if !filepath.IsAbs(p) {
		return "", fmt.Errorf("%w: path must be absolute", ErrForbidden)
	}
	clean := filepath.Clean(p)

	real, err := resolveReal(clean)
	if err != nil {
		return "", err
	}

	roots := o.settings.Roots()
	if len(roots) == 0 {
		return real, nil
	}

	for _, root := range roots {
		if isUnder(real, root) {
			return real, nil
		}
	}
	return "", fmt.Errorf("%w: %s", ErrForbidden, p)
}

// resolveReal returns the symlink-free form of a cleaned, absolute path.
//
// If the path exists it is simply EvalSymlinks'd. If it (or any part of it)
// doesn't exist yet — e.g. create/rename/upload destinations — symlinks are
// resolved on the deepest existing ancestor only, and the non-existent
// suffix is re-joined onto that resolved ancestor. This prevents a symlink
// placed inside the jail (e.g. jail/link -> /etc) from letting a
// not-yet-created path (jail/link/newfile) pass the jail check while the
// later os.MkdirAll/os.Create follows the symlink outside the jail.
func resolveReal(clean string) (string, error) {
	real, err := filepath.EvalSymlinks(clean)
	if err == nil {
		return real, nil
	}
	if !os.IsNotExist(err) {
		// Anything other than "doesn't exist yet" (e.g. ENOTDIR because a
		// path component is a regular file, or a permission error) is a
		// real problem the caller's filesystem op would hit anyway —
		// surface it instead of guessing at a fallback path.
		return "", err
	}

	// Walk up to the deepest existing ancestor.
	dir := clean
	var suffix []string
	for {
		parent := filepath.Dir(dir)
		if parent == dir {
			// Reached the filesystem root without finding an existing
			// ancestor; nothing to resolve against.
			return clean, nil
		}
		suffix = append([]string{filepath.Base(dir)}, suffix...)
		dir = parent
		if _, statErr := os.Lstat(dir); statErr == nil {
			break
		} else if !os.IsNotExist(statErr) {
			return "", statErr
		}
	}

	realDir, err := filepath.EvalSymlinks(dir)
	if err != nil {
		return "", err
	}

	// Re-join the non-existent suffix onto the resolved ancestor and clean
	// the result so any ".." segments in the suffix are normalized before
	// the jail check.
	return filepath.Clean(filepath.Join(append([]string{realDir}, suffix...)...)), nil
}

// isUnder returns true if p is equal to or a descendant of root.
func isUnder(p, root string) bool {
	root = filepath.Clean(root)
	p = filepath.Clean(p)
	if p == root {
		return true
	}
	return strings.HasPrefix(p, root+string(filepath.Separator))
}
