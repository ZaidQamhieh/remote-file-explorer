use rfe_indexd::filter::{Compiled, Filters};
use rfe_indexd::index::{Index, Limits};
use rfe_indexd::recents;
use std::fs;
use std::path::Path;
use std::sync::atomic::AtomicBool;

fn big() -> Limits {
    Limits {
        max_entries: 1_000_000,
        max_bytes: 1 << 30,
    }
}

fn build(root: &Path) -> Index {
    Index::build(
        &[root.to_str().unwrap().to_string()],
        big(),
        &AtomicBool::new(false),
    )
}

fn all(idx: &Index, root: &Path) -> Vec<String> {
    let r = root.to_str().unwrap().to_string();
    let (entries, _) = idx.query(
        &Compiled::new(Filters::default()),
        std::slice::from_ref(&r),
        100_000,
    );
    entries
        .into_iter()
        .map(|e| {
            e.path
                .strip_prefix(&r)
                .unwrap()
                .trim_start_matches('/')
                .to_string()
        })
        .collect()
}

fn touch(p: &Path) {
    fs::create_dir_all(p.parent().unwrap()).unwrap();
    fs::write(p, b"x").unwrap();
}

#[test]
fn order_is_depth_first_by_name_like_go_walkdir() {
    let t = tempfile::tempdir().unwrap();
    let r = t.path();
    // "a-b" sorts after "a" but a plain byte sort of whole paths would put "a-b" before "a/c".
    touch(&r.join("a/c"));
    touch(&r.join("a-b"));
    touch(&r.join("a/b/z"));
    touch(&r.join("B"));
    touch(&r.join("zeta"));
    let idx = build(r);
    assert_eq!(
        all(&idx, r),
        vec!["B", "a", "a/b", "a/b/z", "a/c", "a-b", "zeta"]
    );
}

#[test]
fn hidden_and_dependency_directories_are_pruned_but_hidden_files_are_kept() {
    let t = tempfile::tempdir().unwrap();
    let r = t.path();
    touch(&r.join(".cache/x"));
    touch(&r.join("node_modules/pkg/index.js"));
    touch(&r.join(".hidden-file"));
    touch(&r.join("src/main.rs"));
    let idx = build(r);
    assert_eq!(all(&idx, r), vec![".hidden-file", "src", "src/main.rs"]);
}

#[cfg(unix)]
#[test]
fn symlinks_are_listed_but_never_followed_out_of_the_root() {
    use std::os::unix::fs::symlink;
    let t = tempfile::tempdir().unwrap();
    let root = t.path().join("root");
    let outside = t.path().join("outside");
    touch(&root.join("inside/file.txt"));
    touch(&outside.join("secret.txt"));
    symlink(&outside, root.join("escape")).unwrap();
    symlink("inside", root.join("alias")).unwrap();
    symlink("nowhere", root.join("broken")).unwrap();
    let idx = build(&root);
    let names = all(&idx, &root);
    assert!(
        names.contains(&"escape".to_string()),
        "the link itself is an entry"
    );
    assert!(
        !names.iter().any(|n| n.contains("secret.txt")),
        "nothing behind an escaping link is listed: {names:?}"
    );
    assert!(
        !names.iter().any(|n| n.starts_with("alias/")),
        "links are not traversed: {names:?}"
    );

    let r = root.to_str().unwrap().to_string();
    let (entries, _) = idx.query(&Compiled::new(Filters::default()), &[r], 1000);
    let by = |n: &str| {
        entries
            .iter()
            .find(|e| e.path.ends_with(n))
            .unwrap()
            .clone()
    };
    assert!(
        by("/alias").is_symlink && by("/alias").is_dir,
        "a link to an in-root directory reports as a directory"
    );
    assert!(
        by("/escape").is_symlink && !by("/escape").is_dir,
        "a link out of the root is not a directory"
    );
    assert_eq!(by("/broken").symlink_target, "nowhere");
    assert!(!by("/inside").is_symlink && by("/inside").is_dir);
}

#[test]
fn filters_roots_and_limit() {
    let t = tempfile::tempdir().unwrap();
    let r = t.path();
    touch(&r.join("docs/Report.PDF"));
    touch(&r.join("docs/notes.txt"));
    touch(&r.join("pics/a.jpg"));
    touch(&r.join("pics2/b.jpg"));
    let idx = build(r);
    let rs = r.to_str().unwrap().to_string();

    let q = |f: Filters, roots: &[String], limit| idx.query(&Compiled::new(f), roots, limit);
    let (e, _) = q(
        Filters {
            needle: "report".into(),
            ..Default::default()
        },
        std::slice::from_ref(&rs),
        10,
    );
    assert_eq!(e.len(), 1);
    assert!(e[0].path.ends_with("docs/Report.PDF"));

    let (e, _) = q(
        Filters {
            exts: Some(vec!["jpg".into()]),
            ..Default::default()
        },
        std::slice::from_ref(&rs),
        10,
    );
    assert_eq!(e.len(), 2);

    // A narrower root must not leak a sibling that only shares a name prefix ("pics" vs "pics2").
    let pics = format!("{rs}/pics");
    let (e, _) = q(
        Filters {
            exts: Some(vec!["jpg".into()]),
            ..Default::default()
        },
        &[pics],
        10,
    );
    assert_eq!(e.len(), 1);
    assert!(e[0].path.ends_with("pics/a.jpg"));

    let (e, truncated) = q(Filters::default(), &[rs], 2);
    assert_eq!(e.len(), 2);
    assert!(truncated, "hitting the limit reports truncation");
}

#[test]
fn budget_truncates_flags_it_and_stays_bounded() {
    let t = tempfile::tempdir().unwrap();
    let r = t.path();
    for i in 0..50 {
        touch(&r.join(format!("d{i:02}/f")));
    }
    let idx = Index::build(
        &[r.to_str().unwrap().to_string()],
        Limits {
            max_entries: 10,
            max_bytes: 1 << 30,
        },
        &AtomicBool::new(false),
    );
    assert!(idx.stats.truncated);
    assert_eq!(idx.stats.entries, 10);
    let names = all(&idx, r);
    // The walk is parallel, so which entries survive an over-budget tree is not guaranteed to match Go's
    // depth-first cut; what is guaranteed is the flag, the bound, and DFS order among the entries kept.
    let mut sorted = names.clone();
    sorted.sort();
    assert_eq!(names, sorted, "kept entries stay in name order");
}

#[test]
fn entries_cost_far_less_than_the_go_index() {
    let t = tempfile::tempdir().unwrap();
    let r = t.path();
    for d in 0..20 {
        for f in 0..200 {
            touch(&r.join(format!("project-{d}/src/module-{f:03}.rs")));
        }
    }
    let idx = build(r);
    let per_entry = idx.stats.bytes / idx.stats.entries;
    // The Go index spends about 394 bytes per entry (measured); this one must stay well under half of that.
    assert!(per_entry < 120, "{per_entry} bytes per entry");
}

#[test]
fn unreadable_or_missing_roots_are_skipped() {
    let idx = Index::build(
        &["/definitely/not/here".to_string()],
        big(),
        &AtomicBool::new(false),
    );
    assert_eq!(idx.stats.entries, 0);
    assert!(idx.is_empty());
}

#[test]
fn recents_returns_newest_files_only() {
    let t = tempfile::tempdir().unwrap();
    let r = t.path();
    let mk = |name: &str, age_secs: u64| {
        let p = r.join(name);
        touch(&p);
        let when = std::time::SystemTime::now() - std::time::Duration::from_secs(age_secs);
        fs::File::options()
            .write(true)
            .open(&p)
            .unwrap()
            .set_modified(when)
            .unwrap();
    };
    mk("old.txt", 5000);
    mk("sub/mid.txt", 3000);
    mk("new.txt", 10);
    mk(".hidden/skipped.txt", 1);
    fs::create_dir_all(r.join("emptydir")).unwrap();
    let (e, partial) = recents::scan(
        &[r.to_str().unwrap().to_string()],
        2,
        None,
        &AtomicBool::new(false),
    );
    assert!(!partial);
    let names: Vec<_> = e
        .iter()
        .map(|x| x.path.rsplit('/').next().unwrap().to_string())
        .collect();
    assert_eq!(
        names,
        vec!["new.txt", "mid.txt"],
        "newest first, directories and hidden dirs excluded"
    );
}

#[test]
fn recents_deadline_marks_a_partial_result() {
    let t = tempfile::tempdir().unwrap();
    touch(&t.path().join("a/b/c.txt"));
    let past = std::time::Instant::now() - std::time::Duration::from_secs(1);
    let (_, partial) = recents::scan(
        &[t.path().to_str().unwrap().to_string()],
        5,
        Some(past),
        &AtomicBool::new(false),
    );
    assert!(partial);
}
