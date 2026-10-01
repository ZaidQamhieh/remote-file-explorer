//! A parallel directory walk built on rooted directory handles.
//!
//! Every directory is opened relative to its parent's handle and never through a symlink that leaves the
//! root, so a link swapped in during the walk cannot make it list files outside the roots it was given.

use cap_std::ambient_authority;
use cap_std::fs::Dir;
use std::ffi::OsString;
use std::sync::Arc;

/// A subdirectory to descend into.
pub struct Sub {
    pub name: OsString,
    pub path: String,
    pub id: u32,
}

/// What a walk does with each directory. `visit` lists one directory and returns the subdirectories to recurse
/// into; it runs on rayon worker threads, so implementations must be `Sync`.
pub trait Visitor: Sync {
    fn visit(&self, dir: &Dir, dir_path: &str, id: u32) -> Vec<Sub>;
    /// Checked before each directory is opened; true stops the walk early (cancel, budget, deadline).
    fn stop(&self) -> bool;
}

/// Walks `root` (an absolute path) in parallel. A root that cannot be opened is skipped silently.
pub fn par_walk<V: Visitor>(v: &V, root: &str, root_id: u32) {
    let Ok(dir) = Dir::open_ambient_dir(root, ambient_authority()) else {
        return;
    };
    rayon::scope(|s| descend(s, v, Arc::new(dir), root.to_string(), root_id));
}

fn descend<'s, V: Visitor>(s: &rayon::Scope<'s>, v: &'s V, dir: Arc<Dir>, path: String, id: u32) {
    if v.stop() {
        return;
    }
    let subs = v.visit(&dir, &path, id);
    for sub in subs {
        let parent = Arc::clone(&dir);
        s.spawn(move |s| {
            if v.stop() {
                return;
            }
            // open_dir never follows a link out of the sandbox; failures (permissions, a vanished dir) skip it.
            if let Ok(child) = parent.open_dir(&sub.name) {
                drop(parent);
                descend(s, v, Arc::new(child), sub.path, sub.id);
            }
        });
    }
}

/// Directories a walk prunes (never the root itself): Linux pseudo-filesystems, hidden directories and
/// dependency caches. Same rule as the Go agent's `shouldSkipVirtualDir`.
pub fn should_skip_dir(name: &str, full_path: &str) -> bool {
    #[cfg(target_os = "linux")]
    if matches!(full_path, "/proc" | "/sys" | "/dev" | "/sysroot") {
        return true;
    }
    let _ = full_path;
    (name.len() > 1 && name.starts_with('.')) || name == "node_modules"
}
