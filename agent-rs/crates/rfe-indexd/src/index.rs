//! The compact in-memory index. Entries live in one chunk per directory: the directory path is stored once and
//! each entry keeps only its name plus a fixed-size record, so an entry costs about 55 bytes instead of the ~400
//! the Go index spends. A query walks the chunks in the same depth-first, name-sorted order Go's `fs.WalkDir`
//! produces, which keeps result order identical.

use crate::entry::{join_path, link_info, stat_of, WireEntry};
use crate::filter::{Compiled, RootScopes};
use crate::walk::{self, At, Sub, Visitor};
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicUsize, Ordering};
use std::sync::Mutex;
use std::time::Instant;

const NO_CHILD: u32 = u32::MAX;
const FLAG_DIR: u8 = 1;
const FLAG_SYMLINK: u8 = 2;
/// Fixed cost per record plus a rough allowance for the chunk's own allocations.
const REC_BYTES: usize = std::mem::size_of::<Rec>();
const CHUNK_OVERHEAD: usize = 96;

#[derive(Debug, Clone, Copy)]
struct Rec {
    name_off: u32,
    name_len: u16,
    flags: u8,
    /// Chunk id of this directory's own listing, or `NO_CHILD`.
    child: u32,
    mode: u32,
    size: u64,
    mtime_ns: i64,
    ctime_ns: i64,
}

#[derive(Debug)]
struct Chunk {
    id: u32,
    dir_path: String,
    names: Vec<u8>,
    recs: Vec<Rec>,
    /// (record index, link target), sorted by record index.
    links: Vec<(u32, String)>,
}

impl Chunk {
    fn name(&self, r: &Rec) -> &str {
        // Names were validated as UTF-8 when stored.
        std::str::from_utf8(
            &self.names[r.name_off as usize..r.name_off as usize + r.name_len as usize],
        )
        .unwrap_or("")
    }

    fn bytes(&self) -> usize {
        self.names.len() + self.recs.len() * REC_BYTES + self.dir_path.len() + CHUNK_OVERHEAD
    }

    fn link_target(&self, rec_idx: usize) -> &str {
        match self
            .links
            .binary_search_by_key(&(rec_idx as u32), |(i, _)| *i)
        {
            Ok(p) => &self.links[p].1,
            Err(_) => "",
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Stats {
    pub entries: usize,
    pub truncated: bool,
    pub build_ms: u64,
    pub bytes: usize,
}

#[derive(Debug, Clone, Copy)]
pub struct Limits {
    pub max_entries: usize,
    pub max_bytes: usize,
}

#[derive(Debug)]
pub struct Index {
    chunks: Vec<Chunk>,
    /// Chunk id -> position in `chunks` (`NO_CHILD` for a directory that could not be listed).
    id_to_pos: Vec<u32>,
    /// (root path, root chunk position)
    roots: Vec<(String, u32)>,
    /// Entries visible to queries, in depth-first order across `roots`; anything past this was over budget.
    visible: usize,
    pub stats: Stats,
}

struct Builder<'a> {
    next_id: AtomicU32,
    chunks: Mutex<Vec<Chunk>>,
    entries: AtomicUsize,
    bytes: AtomicUsize,
    hard_entries: usize,
    hard_bytes: usize,
    over: AtomicBool,
    cancel: &'a AtomicBool,
}

impl Visitor for Builder<'_> {
    fn visit(&self, at: &At, id: u32) -> Vec<Sub> {
        let (dir, dir_path) = (at.dir, at.path);
        let mut chunk = Chunk {
            id,
            dir_path: dir_path.to_string(),
            names: Vec::new(),
            recs: Vec::new(),
            links: Vec::new(),
        };
        let mut subs: Vec<Sub> = Vec::new();
        let Ok(rd) = dir.entries() else {
            return Vec::new();
        };
        // Collected first so the records can be sorted by name, which is the order fs.WalkDir yields.
        struct Raw {
            name: String,
            os: std::ffi::OsString,
            meta: cap_std::fs::Metadata,
            walk_into: bool,
        }
        let mut raws: Vec<Raw> = Vec::new();
        for ent in rd {
            let Ok(ent) = ent else { continue };
            let os = ent.file_name();
            let Some(name) = os.to_str() else { continue };
            if name.len() > u16::MAX as usize {
                continue;
            }
            let Ok(ft) = ent.file_type() else { continue };
            let Ok(meta) = ent.metadata() else { continue };
            let walk_into = ft.is_dir();
            if walk_into && walk::should_skip_dir(name, &join_path(dir_path, name)) {
                continue;
            }
            raws.push(Raw {
                name: name.to_string(),
                os,
                meta,
                walk_into,
            });
        }
        raws.sort_unstable_by(|a, b| a.name.as_bytes().cmp(b.name.as_bytes()));
        for raw in raws {
            let st = stat_of(&raw.meta);
            let is_symlink = raw.meta.file_type().is_symlink();
            let mut flags = 0u8;
            let mut is_dir = raw.meta.is_dir();
            let mut link_target = String::new();
            if is_symlink {
                flags |= FLAG_SYMLINK;
                (is_dir, link_target) = link_info(at.root, dir, at.rel, &raw.os);
            }
            if is_dir {
                flags |= FLAG_DIR;
            }
            let rec_idx = chunk.recs.len();
            if !link_target.is_empty() {
                chunk.links.push((rec_idx as u32, link_target));
            }
            let mut child = NO_CHILD;
            if raw.walk_into {
                child = self.next_id.fetch_add(1, Ordering::Relaxed);
                subs.push(Sub {
                    name: raw.os,
                    path: join_path(dir_path, &raw.name),
                    id: child,
                });
            }
            let name_off = chunk.names.len() as u32;
            chunk.names.extend_from_slice(raw.name.as_bytes());
            chunk.recs.push(Rec {
                name_off,
                name_len: raw.name.len() as u16,
                flags,
                child,
                mode: st.mode,
                size: st.size,
                mtime_ns: st.mtime_ns,
                ctime_ns: st.ctime_ns,
            });
        }
        chunk.names.shrink_to_fit();
        chunk.recs.shrink_to_fit();
        let n = chunk.recs.len();
        let b = chunk.bytes();
        self.chunks.lock().unwrap().push(chunk);
        let total_n = self.entries.fetch_add(n, Ordering::Relaxed) + n;
        let total_b = self.bytes.fetch_add(b, Ordering::Relaxed) + b;
        if total_n >= self.hard_entries || total_b >= self.hard_bytes {
            self.over.store(true, Ordering::Relaxed);
        }
        subs
    }

    fn stop(&self) -> bool {
        self.cancel.load(Ordering::Relaxed) || self.over.load(Ordering::Relaxed)
    }
}

impl Index {
    /// Walks `roots` in parallel and builds the index. `cancel` aborts the build (the partial result is dropped by
    /// the caller).
    pub fn build(roots: &[String], limits: Limits, cancel: &AtomicBool) -> Index {
        let started = Instant::now();
        let b = Builder {
            next_id: AtomicU32::new(0),
            chunks: Mutex::new(Vec::new()),
            entries: AtomicUsize::new(0),
            bytes: AtomicUsize::new(0),
            // The walk may overshoot the budget (it is parallel); the tail is cut in depth-first order afterwards.
            hard_entries: limits.max_entries.saturating_mul(3) / 2,
            hard_bytes: limits.max_bytes.saturating_mul(3) / 2,
            over: AtomicBool::new(false),
            cancel,
        };
        let mut root_ids = Vec::new();
        for root in roots {
            let id = b.next_id.fetch_add(1, Ordering::Relaxed);
            root_ids.push((root.clone(), id));
            walk::par_walk(&b, root, id);
        }
        let mut chunks = b.chunks.into_inner().unwrap();
        chunks.sort_unstable_by_key(|c| c.id);
        let max_id = b.next_id.load(Ordering::Relaxed) as usize;
        let mut id_to_pos = vec![NO_CHILD; max_id];
        for (pos, c) in chunks.iter().enumerate() {
            id_to_pos[c.id as usize] = pos as u32;
        }
        let roots: Vec<(String, u32)> = root_ids
            .into_iter()
            .map(|(p, id)| (p, id_to_pos.get(id as usize).copied().unwrap_or(NO_CHILD)))
            .collect();
        let mut idx = Index {
            chunks,
            id_to_pos,
            roots,
            visible: usize::MAX,
            stats: Stats::default(),
        };
        let (visible, bytes, truncated) = idx.apply_budget(limits, b.over.load(Ordering::Relaxed));
        idx.visible = visible;
        idx.stats = Stats {
            entries: visible,
            truncated,
            build_ms: started.elapsed().as_millis() as u64,
            bytes,
        };
        idx
    }

    /// Counts entries in depth-first order until a limit is hit.
    fn apply_budget(&self, limits: Limits, walk_overshot: bool) -> (usize, usize, bool) {
        let mut entries = 0usize;
        let mut bytes = 0usize;
        let mut truncated = walk_overshot;
        self.dfs(|chunk, i| {
            // Real per-entry cost: the record plus its name (the directory path is shared).
            let cost = REC_BYTES + chunk.recs[i].name_len as usize;
            if entries >= limits.max_entries || bytes + cost > limits.max_bytes {
                truncated = true;
                return false;
            }
            entries += 1;
            bytes += cost;
            true
        });
        // Report real memory use, not the budget estimate.
        let real: usize = self.chunks.iter().map(Chunk::bytes).sum();
        (entries, real, truncated)
    }

    /// Depth-first, name-sorted traversal over every root. The callback returns false to stop.
    fn dfs<F: FnMut(&Chunk, usize) -> bool>(&self, mut f: F) {
        for (_, root_pos) in &self.roots {
            if *root_pos == NO_CHILD {
                continue;
            }
            let mut stack: Vec<(u32, usize)> = vec![(*root_pos, 0)];
            while let Some((pos, i)) = stack.pop() {
                let chunk = &self.chunks[pos as usize];
                if i >= chunk.recs.len() {
                    continue;
                }
                // Resume this directory after the current entry once its subtree is done.
                stack.push((pos, i + 1));
                if !f(chunk, i) {
                    return;
                }
                let child = chunk.recs[i].child;
                if child != NO_CHILD {
                    let cpos = self
                        .id_to_pos
                        .get(child as usize)
                        .copied()
                        .unwrap_or(NO_CHILD);
                    if cpos != NO_CHILD {
                        stack.push((cpos, 0));
                    }
                }
            }
        }
    }

    pub fn is_empty(&self) -> bool {
        self.stats.entries == 0
    }

    /// Matches in index order. The bool is true when `limit` was reached or the index itself was truncated.
    pub fn query(
        &self,
        filters: &Compiled,
        roots: &[String],
        limit: usize,
    ) -> (Vec<WireEntry>, bool) {
        let scopes = RootScopes::new(roots);
        let mut out: Vec<WireEntry> = Vec::new();
        let mut hit_limit = false;
        let mut seen = 0usize;
        let visible = self.visible;
        self.dfs(|chunk, i| {
            if seen >= visible {
                return false;
            }
            seen += 1;
            let r = &chunk.recs[i];
            let name = chunk.name(r);
            let is_dir = r.flags & FLAG_DIR != 0;
            if !filters.match_name(name) || !filters.match_attrs(name, is_dir, r.size, r.mtime_ns) {
                return true;
            }
            let path = join_path(&chunk.dir_path, name);
            if !scopes.contains(&path) {
                return true;
            }
            out.push(WireEntry {
                path,
                size: r.size,
                mtime_ns: r.mtime_ns,
                ctime_ns: r.ctime_ns,
                mode: r.mode,
                is_dir,
                is_symlink: r.flags & FLAG_SYMLINK != 0,
                symlink_target: chunk.link_target(i).to_string(),
            });
            if out.len() >= limit {
                hit_limit = true;
                return false;
            }
            true
        });
        (out, self.stats.truncated || hit_limit)
    }
}
