//! Looking for a newer version and fetching its package, against a small local stand-in for
//! GitHub's list of releases. The package is only kept when its SHA-256 is the one the release lists.

use rfe_desktop_lib::updates::{check_at, download_at, notes_of, package_for, sum_for, Version};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::{Arc, Mutex};
use tempfile::TempDir;

/// A stand-in for GitHub: serves bodies by path, and a list of releases whose download links point
/// back at this very server.
struct Site {
    base: String,
    hits: Arc<Mutex<Vec<String>>>,
}

/// `releases` is `(tag, prerelease, draft, files)`; every file is served at `/dl/<tag>/<name>`.
/// One release: tag, draft, prerelease, and its files.
type Release<'a> = (&'a str, bool, bool, Vec<(&'a str, Vec<u8>)>);

fn site(releases: &[Release<'_>]) -> Site {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let mut routes: HashMap<String, Vec<u8>> = HashMap::new();
    let mut list = Vec::new();
    for (tag, pre, draft, files) in releases {
        let refs: Vec<(&str, &[u8])> = files.iter().map(|(n, b)| (*n, b.as_slice())).collect();
        list.push(release(&base, tag, *pre, *draft, &refs));
        for (n, b) in files {
            routes.insert(format!("/dl/{tag}/{n}"), b.clone());
        }
    }
    routes.insert("/list".into(), serde_json::to_vec(&list).unwrap());
    let hits = Arc::new(Mutex::new(Vec::new()));
    let seen = hits.clone();
    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let routes = routes.clone();
            let seen = seen.clone();
            std::thread::spawn(move || {
                let mut stream = stream;
                let mut buf = [0u8; 4096];
                let n = stream.read(&mut buf).unwrap_or(0);
                let head = String::from_utf8_lossy(&buf[..n]).to_string();
                let path = head
                    .lines()
                    .next()
                    .and_then(|l| l.split(' ').nth(1))
                    .unwrap_or("/")
                    .to_string();
                seen.lock().unwrap().push(path.clone());
                let (status, body) = match routes.get(&path) {
                    Some(b) => ("200 OK", b.clone()),
                    None => ("404 Not Found", b"no".to_vec()),
                };
                let _ = write!(
                    stream,
                    "HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                    body.len()
                );
                let _ = stream.write_all(&body);
            });
        }
    });
    Site { base, hits }
}

fn release(
    base: &str,
    tag: &str,
    pre: bool,
    draft: bool,
    files: &[(&str, &[u8])],
) -> serde_json::Value {
    serde_json::json!({
        "tag_name": tag, "prerelease": pre, "draft": draft,
        "body": "## What's new\n- Faster folders\n- A fix\n",
        "html_url": format!("https://github.com/x/y/releases/tag/{tag}"),
        "assets": files.iter().map(|(n, b)| serde_json::json!({
            "name": n, "size": b.len(), "browser_download_url": format!("{base}/dl/{tag}/{n}")
        })).collect::<Vec<_>>()
    })
}

#[test]
fn versions_order_like_semver() {
    let v = |s: &str| Version::parse(s).unwrap();
    assert!(v("1.0.1") > v("1.0.0"));
    assert!(v("1.10.0") > v("1.9.9"));
    assert!(v("1.1.0-rc.1") < v("1.1.0"));
    assert!(v("1.1.0-rc.2") > v("1.1.0-rc.1"));
    assert!(v("1.1.0-rc.10") > v("1.1.0-rc.2"));
    assert!(v("1.1.0-beta") < v("1.1.0-rc.1"));
    assert!(v("1.0.0") > v("0.9.9-rc.1"));
    assert_eq!(v("v1.2.3"), v("1.2.3"));
    for bad in [
        "",
        "1",
        "1.2",
        "1.2.3.4",
        "a.b.c",
        "1.2.3-",
        "1.2.x",
        "1.2.3-a..b",
    ] {
        assert!(Version::parse(bad).is_none(), "{bad}");
    }
    assert!(v("1.0.0-rc.1").is_pre() && !v("1.0.0").is_pre());
}

#[test]
fn notes_lose_their_markdown_and_are_short() {
    let n = notes_of("## What's new\n- Faster folders\n* A fix\n\n   \n");
    assert_eq!(n, ["What's new", "Faster folders", "A fix"]);
    let many = (0..40)
        .map(|i| format!("- line {i}"))
        .collect::<Vec<_>>()
        .join("\n");
    assert_eq!(notes_of(&many).len(), 8);
}

#[test]
fn the_package_follows_how_the_app_runs() {
    let names = [
        "SHA256SUMS",
        "RFE-Desktop_1.1.0_amd64.deb",
        "RFE-Desktop_1.1.0_amd64.AppImage",
    ];
    assert_eq!(
        package_for(names.iter().copied(), false),
        Some("RFE-Desktop_1.1.0_amd64.deb")
    );
    assert_eq!(
        package_for(names.iter().copied(), true),
        Some("RFE-Desktop_1.1.0_amd64.AppImage")
    );
    assert_eq!(package_for(["SHA256SUMS"].into_iter(), false), None);
}

#[test]
fn a_sums_file_names_each_package_once() {
    let h = "a".repeat(64);
    let sums = format!(
        "{h}  one.deb\n{}  two.AppImage\nnot a line\n",
        "B".repeat(64)
    );
    assert_eq!(sum_for(&sums, "one.deb"), Some(h));
    assert_eq!(sum_for(&sums, "two.AppImage"), Some("b".repeat(64)));
    assert_eq!(sum_for(&sums, "three.deb"), None);
    assert_eq!(
        sum_for(&format!("{}  x.deb", "z".repeat(64)), "x.deb"),
        None,
        "not hex"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn a_check_picks_the_newest_release_of_the_channel() {
    let s = site(&[
        ("desktop-v1.2.0-rc.1", true, false, vec![]),
        (
            "desktop-v1.1.0",
            false,
            false,
            vec![
                ("a.deb", b"x".to_vec()),
                ("a.AppImage", b"yy".to_vec()),
                ("SHA256SUMS", vec![]),
            ],
        ),
        ("desktop-v1.3.0", false, true, vec![]),
        ("v9.9.9", false, false, vec![]),
        ("desktop-v1.0.0", false, false, vec![]),
    ]);
    let url = format!("{}/list", s.base);

    let stable = check_at(&url, "1.0.0", false, false).await.unwrap();
    assert_eq!(
        (stable.latest.as_str(), stable.available, stable.prerelease),
        ("1.1.0", true, false)
    );
    assert_eq!(stable.notes, ["What's new", "Faster folders", "A fix"]);
    assert_eq!(stable.package.as_ref().unwrap().name, "a.deb");
    assert!(stable.page.starts_with("https://github.com/"));
    let app_image = check_at(&url, "1.0.0", false, true).await.unwrap();
    assert_eq!(app_image.package.unwrap().name, "a.AppImage");

    let beta = check_at(&url, "1.0.0", true, false).await.unwrap();
    assert_eq!(
        (beta.latest.as_str(), beta.prerelease),
        ("1.2.0-rc.1", true)
    );

    let same = check_at(&url, "1.1.0", false, false).await.unwrap();
    assert!(!same.available, "{same:?}");
    assert!(same.notes.is_empty());
    let newer = check_at(&url, "2.0.0", false, false).await.unwrap();
    assert!(
        !newer.available,
        "a newer app than any release is up to date"
    );

    let none = check_at(&format!("{}/empty", s.base), "1.0.0", false, false).await;
    assert!(
        none.unwrap_err().contains("404"),
        "a 404 is an error with a message"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn a_package_is_kept_only_when_its_checksum_matches() {
    let body = vec![7u8; 100_000];
    let name = "RFE-Desktop_1.1.0_amd64.deb";
    let good = format!("{}  {name}\n", hex::encode(Sha256::digest(&body)));
    let bad = format!("{}  {name}\n", "0".repeat(64));
    for (sums, kept) in [(good, true), (bad, false)] {
        let s = site(&[(
            "desktop-v1.1.0",
            false,
            false,
            vec![(name, body.clone()), ("SHA256SUMS", sums.into_bytes())],
        )]);
        let dir = TempDir::new().unwrap();
        let got = download_at(&format!("{}/list", s.base), "1.1.0", name, dir.path()).await;
        if kept {
            let path = got.unwrap();
            assert_eq!(std::fs::read(&path).unwrap(), body);
            assert_eq!(path.file_name().unwrap().to_str().unwrap(), name);
            assert_eq!(
                std::fs::read_dir(dir.path()).unwrap().count(),
                1,
                "no part file stays"
            );
        } else {
            let e = got.unwrap_err();
            assert!(e.contains("does not match"), "{e}");
            assert!(
                std::fs::read_dir(dir.path()).unwrap().next().is_none(),
                "nothing may stay behind"
            );
        }
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_release_without_checksums_is_not_downloaded() {
    let s = site(&[(
        "desktop-v1.1.0",
        false,
        false,
        vec![("a.deb", b"abc".to_vec())],
    )]);
    let dir = TempDir::new().unwrap();
    let e = download_at(&format!("{}/list", s.base), "1.1.0", "a.deb", dir.path())
        .await
        .unwrap_err();
    assert!(e.contains("no SHA256SUMS"), "{e}");
    assert!(
        s.hits.lock().unwrap().iter().all(|p| !p.ends_with("a.deb")),
        "the package was never fetched"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn a_package_that_is_not_listed_or_not_a_package_is_refused() {
    let sums = format!("{}  a.deb\n", hex::encode(Sha256::digest(b"abc")));
    let s = site(&[(
        "desktop-v1.1.0",
        false,
        false,
        vec![
            ("a.deb", b"abc".to_vec()),
            ("SHA256SUMS", sums.into_bytes()),
        ],
    )]);
    let url = format!("{}/list", s.base);
    let dir = TempDir::new().unwrap();
    let e = download_at(&url, "1.1.0", "other.deb", dir.path())
        .await
        .unwrap_err();
    assert!(e.contains("no such package"), "{e}");
    let e = download_at(&url, "9.9.9", "a.deb", dir.path())
        .await
        .unwrap_err();
    assert!(e.contains("no longer listed"), "{e}");
    let e = download_at(&url, "1.1.0", "SHA256SUMS", dir.path())
        .await
        .unwrap_err();
    assert!(e.contains("not a package"), "{e}");
    assert!(
        s.hits.lock().unwrap().iter().all(|p| !p.ends_with("a.deb")),
        "nothing was fetched"
    );
    assert!(std::fs::read_dir(dir.path()).unwrap().next().is_none());
}
