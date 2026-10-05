//! Looking for a newer RFE Desktop on the project's GitHub releases, and fetching it.
//!
//! The app never installs anything by itself. A check reads the public list of releases (tags
//! `desktop-vX.Y.Z`, with a pre-release for the beta channel) and says what is newer than this
//! version. A download takes the package that fits how the app runs (the AppImage when it runs from
//! one, else the `.deb`) into the downloads folder, compares its SHA-256 with the release's
//! `SHA256SUMS` file and only then gives it its name. Installing is left to the person: the
//! package manager for a `.deb`, a double click for an AppImage.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::cmp::Ordering;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Duration;

/// The releases of the project, newest first.
pub const RELEASES_URL: &str =
    "https://api.github.com/repos/ZaidQamhieh/remote-file-explorer/releases?per_page=50";
const TAG_PREFIX: &str = "desktop-v";
/// The biggest package this app will fetch.
const MAX_PACKAGE: u64 = 400 << 20;
const MAX_LIST: usize = 4 << 20;
const MAX_NOTES: usize = 2000;

#[derive(Deserialize)]
struct ApiAsset {
    name: String,
    size: u64,
    browser_download_url: String,
}

#[derive(Deserialize)]
struct ApiRelease {
    tag_name: String,
    #[serde(default)]
    body: String,
    #[serde(default)]
    draft: bool,
    #[serde(default)]
    prerelease: bool,
    #[serde(default)]
    html_url: String,
    #[serde(default)]
    assets: Vec<ApiAsset>,
}

/// One package a release offers.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Package {
    pub name: String,
    pub size: u64,
}

/// What the check found.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateView {
    /// The version of this app.
    pub current: String,
    /// The newest version on the chosen channel, which can be the current one.
    pub latest: String,
    pub available: bool,
    pub prerelease: bool,
    pub notes: Vec<String>,
    pub page: String,
    /// The package `update_download` would fetch, if the release has one for this system.
    pub package: Option<Package>,
}

/// `major.minor.patch` and an optional pre-release part, for ordering versions.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Version {
    core: [u64; 3],
    pre: Vec<String>,
}

impl Version {
    pub fn parse(text: &str) -> Option<Self> {
        let text = text.trim().trim_start_matches('v');
        let (core, pre) = match text.split_once('-') {
            Some((c, p)) => (c, Some(p)),
            None => (text, None),
        };
        let mut parts = core.split('.');
        let mut nums = [0u64; 3];
        for n in nums.iter_mut() {
            *n = parts.next()?.parse().ok()?;
        }
        if parts.next().is_some() {
            return None;
        }
        let pre: Vec<String> = match pre {
            Some("") => return None,
            Some(p) => p.split('.').map(str::to_string).collect(),
            None => Vec::new(),
        };
        if pre
            .iter()
            .any(|s| s.is_empty() || !s.chars().all(|c| c.is_ascii_alphanumeric() || c == '-'))
        {
            return None;
        }
        Some(Self { core: nums, pre })
    }

    pub fn is_pre(&self) -> bool {
        !self.pre.is_empty()
    }
}

impl PartialOrd for Version {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Version {
    fn cmp(&self, other: &Self) -> Ordering {
        self.core.cmp(&other.core).then_with(|| {
            // A version without a pre-release part is newer than the same one with it.
            match (self.pre.is_empty(), other.pre.is_empty()) {
                (true, true) => Ordering::Equal,
                (true, false) => Ordering::Greater,
                (false, true) => Ordering::Less,
                (false, false) => {
                    for (a, b) in self.pre.iter().zip(&other.pre) {
                        let o = match (a.parse::<u64>(), b.parse::<u64>()) {
                            (Ok(x), Ok(y)) => x.cmp(&y),
                            (Ok(_), Err(_)) => Ordering::Less,
                            (Err(_), Ok(_)) => Ordering::Greater,
                            (Err(_), Err(_)) => a.cmp(b),
                        };
                        if o != Ordering::Equal {
                            return o;
                        }
                    }
                    self.pre.len().cmp(&other.pre.len())
                }
            }
        })
    }
}

/// The lines of a release's notes, bullets and headings removed, the first few only.
pub fn notes_of(body: &str) -> Vec<String> {
    body.chars()
        .take(MAX_NOTES * 4)
        .collect::<String>()
        .lines()
        .map(|l| l.trim().trim_start_matches(['-', '*', '#', ' ']).trim())
        .map(|l| crate::desktop::clean_text(l, 160))
        .filter(|l| !l.is_empty())
        .take(8)
        .collect()
}

/// Which package of a release suits how this app runs.
pub fn package_for<'a>(names: impl Iterator<Item = &'a str>, appimage: bool) -> Option<&'a str> {
    let suffix = if appimage { ".AppImage" } else { ".deb" };
    names
        .into_iter()
        .find(|n| n.ends_with(suffix) && !n.contains('/') && !n.contains('\\'))
}

fn client() -> Result<reqwest::Client, String> {
    reqwest::Client::builder()
        .user_agent(format!("RFE-Desktop/{}", env!("CARGO_PKG_VERSION")))
        .timeout(Duration::from_secs(60))
        .connect_timeout(Duration::from_secs(15))
        // Only ever to an https address, so a redirect cannot downgrade the connection.
        .redirect(reqwest::redirect::Policy::custom(|a| {
            if a.previous().len() >= 5 || a.url().scheme() != "https" {
                a.stop()
            } else {
                a.follow()
            }
        }))
        .build()
        .map_err(|e| format!("cannot set up the connection: {e}"))
}

fn offline(e: reqwest::Error) -> String {
    if e.is_timeout() {
        "GitHub did not answer in time. Check the connection and try again.".into()
    } else if e.is_connect() {
        "Cannot reach GitHub. Check the connection and try again.".into()
    } else {
        format!("The update check failed: {}", e.without_url())
    }
}

async fn capped(mut resp: reqwest::Response, max: usize) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    while let Some(chunk) = resp.chunk().await.map_err(offline)? {
        if out.len() + chunk.len() > max {
            return Err("GitHub sent more than was expected".into());
        }
        out.extend_from_slice(&chunk);
    }
    Ok(out)
}

/// Reads the list of releases at `url` and says whether one is newer than `current`.
pub async fn check_at(
    url: &str,
    current: &str,
    beta: bool,
    appimage: bool,
) -> Result<UpdateView, String> {
    let me = Version::parse(current).ok_or("this app's own version is not readable")?;
    let resp = client()?
        .get(url)
        .header("Accept", "application/vnd.github+json")
        .send()
        .await
        .map_err(offline)?;
    if !resp.status().is_success() {
        return Err(format!(
            "GitHub answered {} when asked for the releases.",
            resp.status().as_u16()
        ));
    }
    let list: Vec<ApiRelease> = serde_json::from_slice(&capped(resp, MAX_LIST).await?)
        .map_err(|_| "GitHub's list of releases could not be read".to_string())?;
    let mut best: Option<(Version, &ApiRelease)> = None;
    for r in &list {
        let Some(v) = r.tag_name.strip_prefix(TAG_PREFIX).and_then(Version::parse) else {
            continue;
        };
        if r.draft || ((r.prerelease || v.is_pre()) && !beta) {
            continue;
        }
        if best.as_ref().map_or(true, |(b, _)| v > *b) {
            best = Some((v, r));
        }
    }
    let Some((v, r)) = best else {
        return Ok(UpdateView {
            current: current.to_string(),
            latest: current.to_string(),
            available: false,
            prerelease: false,
            notes: vec![],
            page: String::new(),
            package: None,
        });
    };
    let available = v > me;
    let package = package_for(r.assets.iter().map(|a| a.name.as_str()), appimage).and_then(|n| {
        r.assets.iter().find(|a| a.name == n).map(|a| Package {
            name: a.name.clone(),
            size: a.size,
        })
    });
    Ok(UpdateView {
        current: current.to_string(),
        latest: r.tag_name[TAG_PREFIX.len()..].to_string(),
        available,
        prerelease: v.is_pre() || r.prerelease,
        notes: if available { notes_of(&r.body) } else { vec![] },
        page: if r.html_url.starts_with("https://github.com/") {
            r.html_url.clone()
        } else {
            String::new()
        },
        package,
    })
}

/// The SHA-256 the release's `SHA256SUMS` lists for `name`.
pub fn sum_for(sums: &str, name: &str) -> Option<String> {
    sums.lines().find_map(|l| {
        let (hash, file) = l.split_once(' ')?;
        let file = file.trim_start_matches([' ', '*']);
        (file == name && hash.len() == 64 && hash.chars().all(|c| c.is_ascii_hexdigit()))
            .then(|| hash.to_ascii_lowercase())
    })
}

/// Fetches the package of `tag` named `name` from the release list at `url` into `dir`, checks it
/// against the release's `SHA256SUMS` and returns where it was saved.
pub async fn download_at(
    url: &str,
    tag_version: &str,
    name: &str,
    dir: &Path,
) -> Result<PathBuf, String> {
    let http = client()?;
    let resp = http
        .get(url)
        .header("Accept", "application/vnd.github+json")
        .send()
        .await
        .map_err(offline)?;
    if !resp.status().is_success() {
        return Err(format!(
            "GitHub answered {} when asked for the releases.",
            resp.status().as_u16()
        ));
    }
    let list: Vec<ApiRelease> = serde_json::from_slice(&capped(resp, MAX_LIST).await?)
        .map_err(|_| "GitHub's list of releases could not be read".to_string())?;
    let want = format!("{TAG_PREFIX}{tag_version}");
    let release = list
        .iter()
        .find(|r| r.tag_name == want && !r.draft)
        .ok_or("that release is no longer listed")?;
    let pkg = release
        .assets
        .iter()
        .find(|a| a.name == name)
        .ok_or("that release has no such package")?;
    if pkg.size == 0 || pkg.size > MAX_PACKAGE {
        return Err("that package has a size this app will not fetch".into());
    }
    if !(pkg.name.ends_with(".deb") || pkg.name.ends_with(".AppImage"))
        || pkg.name.contains('/')
        || pkg.name.contains('\\')
        || pkg.name.starts_with('.')
    {
        return Err("that is not a package this app fetches".into());
    }
    let sums_asset = release
        .assets
        .iter()
        .find(|a| a.name == "SHA256SUMS")
        .ok_or("that release has no SHA256SUMS file, so the package cannot be checked")?;
    let sums_resp = http
        .get(&sums_asset.browser_download_url)
        .send()
        .await
        .map_err(offline)?;
    if !sums_resp.status().is_success() {
        return Err("the checksum file of that release could not be fetched".into());
    }
    let sums = String::from_utf8(capped(sums_resp, 1 << 20).await?)
        .map_err(|_| "the checksum file of that release is not text".to_string())?;
    let expect =
        sum_for(&sums, &pkg.name).ok_or("the release's checksums do not list that package")?;

    std::fs::create_dir_all(dir).map_err(|e| format!("cannot use {}: {e}", dir.display()))?;
    // One part file per request, created exclusively: two downloads of the same package never share
    // (and never truncate) each other's bytes.
    static REQUESTS: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let part = dir.join(format!(
        ".rfe-update-{}-{}-{}.part",
        &expect[..12],
        std::process::id(),
        REQUESTS.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
    let result = fetch_checked(&http, &pkg.browser_download_url, &part, pkg.size, &expect).await;
    if let Err(e) = result {
        let _ = std::fs::remove_file(&part);
        return Err(e);
    }
    let dir = dir.to_path_buf();
    let name = pkg.name.clone();
    tokio::task::spawn_blocking(move || crate::transfers::publish_no_clobber(&part, &dir, &name))
        .await
        .map_err(|e| e.to_string())?
        .map_err(|e| format!("the package could not be put in place: {e}"))
}

async fn fetch_checked(
    http: &reqwest::Client,
    url: &str,
    part: &Path,
    size: u64,
    expect: &str,
) -> Result<(), String> {
    let mut resp = http
        .get(url)
        .timeout(Duration::from_secs(1800))
        .send()
        .await
        .map_err(offline)?;
    if !resp.status().is_success() {
        return Err(format!(
            "GitHub answered {} for the package.",
            resp.status().as_u16()
        ));
    }
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(part)
        .map_err(|e| format!("cannot write {}: {e}", part.display()))?;
    let mut hash = Sha256::new();
    let mut got = 0u64;
    while let Some(chunk) = resp.chunk().await.map_err(offline)? {
        got += chunk.len() as u64;
        if got > size.min(MAX_PACKAGE) {
            return Err("GitHub sent more than the package's size".into());
        }
        hash.update(&chunk);
        file.write_all(&chunk)
            .map_err(|e| format!("cannot write {}: {e}", part.display()))?;
    }
    file.flush().map_err(|e| e.to_string())?;
    if got != size {
        return Err("the package ended early; try again".into());
    }
    if !hex::encode(hash.finalize()).eq_ignore_ascii_case(expect) {
        return Err("The package does not match the release's checksum. It was deleted.".into());
    }
    Ok(())
}

// ---- the commands ----

/// Looks for a newer version. `channel` is `stable` or `beta`.
#[tauri::command]
pub async fn update_check(channel: String) -> Result<UpdateView, String> {
    check_at(
        RELEASES_URL,
        env!("CARGO_PKG_VERSION"),
        channel == "beta",
        std::env::var_os("APPIMAGE").is_some(),
    )
    .await
}

/// Fetches the package of release `version` (as `update_check` named it) into the downloads folder
/// and returns its path. Nothing is installed.
#[tauri::command]
pub async fn update_download(
    app: tauri::AppHandle,
    version: String,
    name: String,
) -> Result<String, String> {
    if Version::parse(&version).is_none() {
        return Err("that is not a version".into());
    }
    let dir = crate::transfers::download_folder(&app)?;
    let path = download_at(RELEASES_URL, &version, &name, &dir).await?;
    crate::applog::info("an update package was downloaded and checked");
    Ok(path.display().to_string())
}
