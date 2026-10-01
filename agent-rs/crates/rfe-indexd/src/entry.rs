//! File metadata as it crosses the wire, and the conversions the Go side expects.

use cap_std::fs::{Dir, Metadata};
use serde::Serialize;
use std::ffi::OsStr;

/// One file or directory as returned to the Go agent. Go turns it into an `fsops.Entry` (mime type, mode string
/// and timestamps are derived there so both implementations share one source of truth).
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct WireEntry {
    pub path: String,
    pub size: u64,
    pub mtime_ns: i64,
    pub ctime_ns: i64,
    /// Go `fs.FileMode` bits.
    pub mode: u32,
    pub is_dir: bool,
    pub is_symlink: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub symlink_target: String,
}

/// The fields kept per entry, taken from an lstat (symlinks are not followed).
#[derive(Debug, Clone, Copy)]
pub struct Stat {
    pub size: u64,
    pub mtime_ns: i64,
    pub ctime_ns: i64,
    pub mode: u32,
}

// Go's fs.FileMode bits.
pub const MODE_DIR: u32 = 1 << 31;
pub const MODE_SYMLINK: u32 = 1 << 27;
pub const MODE_DEVICE: u32 = 1 << 26;
pub const MODE_NAMED_PIPE: u32 = 1 << 25;
pub const MODE_SOCKET: u32 = 1 << 24;
pub const MODE_SETUID: u32 = 1 << 23;
pub const MODE_SETGID: u32 = 1 << 22;
pub const MODE_CHAR_DEVICE: u32 = 1 << 21;
pub const MODE_STICKY: u32 = 1 << 20;

#[cfg(not(all(unix, not(target_os = "macos"))))]
fn system_time_ns(t: std::time::SystemTime) -> i64 {
    match t.duration_since(std::time::UNIX_EPOCH) {
        Ok(d) => d.as_nanos().min(i64::MAX as u128) as i64,
        Err(e) => -(e.duration().as_nanos().min(i64::MAX as u128) as i64),
    }
}

#[cfg(unix)]
pub fn stat_of(meta: &Metadata) -> Stat {
    use cap_std::fs::MetadataExt;
    let st_mode = meta.mode();
    // Same mapping as Go's os.fillFileStatFromSys.
    let mut mode = st_mode & 0o777;
    match st_mode & 0o170000 {
        0o060000 => mode |= MODE_DEVICE,
        0o020000 => mode |= MODE_DEVICE | MODE_CHAR_DEVICE,
        0o040000 => mode |= MODE_DIR,
        0o010000 => mode |= MODE_NAMED_PIPE,
        0o120000 => mode |= MODE_SYMLINK,
        0o140000 => mode |= MODE_SOCKET,
        _ => {}
    }
    if st_mode & 0o2000 != 0 {
        mode |= MODE_SETGID;
    }
    if st_mode & 0o4000 != 0 {
        mode |= MODE_SETUID;
    }
    if st_mode & 0o1000 != 0 {
        mode |= MODE_STICKY;
    }
    Stat {
        size: meta.len(),
        mtime_ns: meta
            .mtime()
            .saturating_mul(1_000_000_000)
            .saturating_add(meta.mtime_nsec()),
        // Go's Linux agent reports status-change time as "created"; macOS reports the birth time (see birthtime_*.go).
        ctime_ns: ctime_ns(meta),
        mode,
    }
}

#[cfg(all(unix, not(target_os = "macos")))]
fn ctime_ns(meta: &Metadata) -> i64 {
    use cap_std::fs::MetadataExt;
    meta.ctime()
        .saturating_mul(1_000_000_000)
        .saturating_add(meta.ctime_nsec())
}

#[cfg(target_os = "macos")]
fn ctime_ns(meta: &Metadata) -> i64 {
    meta.created()
        .map(|t| system_time_ns(t.into_std()))
        .unwrap_or(0)
}

#[cfg(not(unix))]
pub fn stat_of(meta: &Metadata) -> Stat {
    let mtime_ns = meta
        .modified()
        .map(|t| system_time_ns(t.into_std()))
        .unwrap_or(0);
    let ctime_ns = meta
        .created()
        .map(|t| system_time_ns(t.into_std()))
        .unwrap_or(mtime_ns);
    let mut mode = if meta.permissions().readonly() {
        0o444
    } else {
        0o666
    };
    if meta.is_dir() {
        mode = MODE_DIR | 0o777;
    } else if meta.file_type().is_symlink() {
        mode |= MODE_SYMLINK;
    }
    Stat {
        size: meta.len(),
        mtime_ns,
        ctime_ns,
        mode,
    }
}

/// The full wire entry for `name` inside `dir`. Symlinks get their target and an `is_dir` that follows the link
/// inside the sandbox (a link that escapes the root reports as a non-directory).
pub fn wire_entry(dir: &Dir, name: &OsStr, path: String, meta: &Metadata) -> WireEntry {
    let st = stat_of(meta);
    let is_symlink = meta.file_type().is_symlink();
    let mut is_dir = meta.is_dir();
    let mut symlink_target = String::new();
    if is_symlink {
        is_dir = dir.metadata(name).map(|m| m.is_dir()).unwrap_or(false);
        if let Ok(t) = dir.read_link(name) {
            symlink_target = t.to_string_lossy().into_owned();
        }
    }
    WireEntry {
        path,
        size: st.size,
        mtime_ns: st.mtime_ns,
        ctime_ns: st.ctime_ns,
        mode: st.mode,
        is_dir,
        is_symlink,
        symlink_target,
    }
}

/// Joins a directory path and a child name with the platform separator (no doubled separator at a root).
pub fn join_path(dir: &str, name: &str) -> String {
    let mut out = String::with_capacity(dir.len() + name.len() + 1);
    out.push_str(dir);
    if !dir.ends_with(std::path::MAIN_SEPARATOR) {
        out.push(std::path::MAIN_SEPARATOR);
    }
    out.push_str(name);
    out
}
