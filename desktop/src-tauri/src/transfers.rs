//! File downloads and uploads against the agent's transfer API, driven from the Rust core.
//!
//! Downloads read `GET /content` in `Range` segments into a hidden part file in the downloads folder
//! and move it to its final name only when it is whole and (when the agent can say) verified, so a
//! cancelled or failed download never leaves a file under a real name. A part file is kept after a
//! failure, and a retry continues from its size. Uploads use the resumable session API: the whole
//! file's SHA-256 is sent when the session opens, every chunk carries its own SHA-256, and the agent
//! verifies the whole file and renames it into place when the upload is completed. A retry asks the
//! agent which chunks it already has and sends only the rest.
//!
//! The window never sees a token or a URL: it starts a transfer by remote or local path and polls
//! `transfer_list`. At most [`PARALLEL`] transfers run at once, the rest wait. The list lives in
//! memory; after a restart the window starts with an empty list (a part file left behind by a crash
//! stays in the downloads folder under a name starting `.rfe-`).

use crate::agent_client::{network_error, response_error, AgentClient, AgentError, CLIENT_VERSION};
use crate::applog;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::fs::File;
use std::future::Future;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, SystemTime};
use tokio::sync::{watch, Semaphore};

/// How many transfers move data at the same time.
pub const PARALLEL: usize = 2;

const DEFAULT_CHUNK: usize = 8 << 20;
// The most an agent may ask for per chunk: a larger answer would make this side allocate it whole.
const MAX_SESSION_CHUNK: usize = 32 << 20;
const DEFAULT_SEGMENT: u64 = 4 << 20;
/// Upper bounds for one request, so a stalled connection ends; a healthy one never gets near them.
const SEGMENT_TIMEOUT: Duration = Duration::from_secs(300);
const CHUNK_TIMEOUT: Duration = Duration::from_secs(600);
/// The agent hashes the whole file before it answers.
const HASH_TIMEOUT: Duration = Duration::from_secs(3600);
const MAX_REMOTE_PATH: usize = 4096;
/// The folder under the user's download folder that holds every download.
pub const FOLDER_NAME: &str = "RFE Desktop";

#[derive(Clone, Copy, Debug)]
pub struct Options {
    /// Upload chunk size in bytes (the agent accepts up to 32 MiB).
    pub chunk_size: usize,
    /// Bytes asked for per download request.
    pub segment_size: u64,
    pub parallel: usize,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            chunk_size: DEFAULT_CHUNK,
            segment_size: DEFAULT_SEGMENT,
            parallel: PARALLEL,
        }
    }
}

/// Where and as whom to talk to the agent. Read again at every start and every retry, so a login that
/// changed in between is used.
#[derive(Clone)]
pub struct Conn {
    pub host: String,
    pub fingerprint: String,
    pub token: String,
}

// Not derived: a `{:?}` in a log line or a test failure must not print the login token.
impl std::fmt::Debug for Conn {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Conn")
            .field("host", &self.host)
            .field("fingerprint", &self.fingerprint)
            .field("token", &"<redacted>")
            .finish()
    }
}

type BoxFuture<T> = Pin<Box<dyn Future<Output = T> + Send>>;
pub type Creds = Arc<dyn Fn() -> BoxFuture<Result<Conn, String>> + Send + Sync>;

/// What one transfer needs from the app: the connection and the downloads folder.
#[derive(Clone)]
pub struct Ctx {
    pub creds: Creds,
    pub download_dir: PathBuf,
}

impl Ctx {
    pub fn fixed(conn: Conn, download_dir: PathBuf) -> Self {
        Self {
            creds: Arc::new(move || {
                let c = conn.clone();
                Box::pin(async move { Ok(c) })
            }),
            download_dir,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Direction {
    Download,
    Upload,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
    Queued,
    Running,
    Done,
    Failed,
    Cancelled,
}

/// What the window shows for one transfer.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferView {
    pub id: String,
    pub direction: Direction,
    pub state: State,
    /// The file's name: the sanitised local name for a download (its final name once done), the
    /// name on the computer for an upload.
    pub name: String,
    pub remote_path: String,
    /// Where a download was saved, or the file an upload reads. Empty until a download is done.
    pub local_path: String,
    pub done: u64,
    /// 0 while the size is not known yet.
    pub total: u64,
    pub error: String,
    /// The agent confirmed the content is intact (a matching SHA-256).
    pub verified: bool,
}

enum Kind {
    Download { part: PathBuf, name: String },
    Upload { src: PathBuf, remote_path: String },
}

/// The same file, as far as a retry can tell.
#[derive(Clone, PartialEq, Debug)]
struct Ident {
    size: u64,
    mtime: Option<SystemTime>,
    id: (u64, u64),
}

#[derive(Clone)]
struct Session {
    id: String,
    chunk_size: usize,
    total_chunks: usize,
}

/// What an upload keeps between attempts.
#[derive(Default)]
struct Resume {
    session: Option<Session>,
    ident: Option<Ident>,
}

struct Item {
    view: Mutex<TransferView>,
    cancel: Mutex<watch::Sender<bool>>,
    ctx: Ctx,
    kind: Kind,
    resume: Mutex<Resume>,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|p| p.into_inner())
}

impl Item {
    fn update(&self, f: impl FnOnce(&mut TransferView)) {
        f(&mut lock(&self.view));
    }

    fn snapshot(&self) -> TransferView {
        lock(&self.view).clone()
    }

    fn set_progress(&self, done: u64, total: u64) {
        self.update(|v| {
            v.done = done;
            v.total = total;
        });
    }
}

struct Inner {
    opts: Options,
    slots: Arc<Semaphore>,
    items: Mutex<Vec<Arc<Item>>>,
}

#[derive(Clone)]
pub struct Transfers {
    inner: Arc<Inner>,
}

impl Default for Transfers {
    fn default() -> Self {
        Self::with_options(Options::default())
    }
}

impl Transfers {
    pub fn with_options(opts: Options) -> Self {
        Self {
            inner: Arc::new(Inner {
                slots: Arc::new(Semaphore::new(opts.parallel.max(1))),
                opts,
                items: Mutex::new(Vec::new()),
            }),
        }
    }

    /// Queues a download of `remote_path` into `ctx.download_dir`. Needs a tokio runtime.
    pub async fn start_download(&self, ctx: Ctx, remote_path: &str) -> Result<String, String> {
        validate_remote(remote_path, "enter the path of the file on the computer")?;
        (ctx.creds)().await?;
        std::fs::create_dir_all(&ctx.download_dir).map_err(|e| {
            format!(
                "cannot use the downloads folder {}: {e}",
                ctx.download_dir.display()
            )
        })?;
        let id = new_id()?;
        let name = safe_name(remote_path);
        let part = ctx.download_dir.join(format!(".rfe-{id}.part"));
        let view = TransferView {
            id: id.clone(),
            direction: Direction::Download,
            state: State::Queued,
            name: name.clone(),
            remote_path: remote_path.to_string(),
            local_path: String::new(),
            done: 0,
            total: 0,
            error: String::new(),
            verified: false,
        };
        self.add(ctx, Kind::Download { part, name }, view);
        Ok(id)
    }

    /// Queues an upload of the regular file at `local_path` into the folder `remote_dir` on the
    /// computer. The file keeps its name and an existing file of that name is never replaced.
    pub async fn start_upload(
        &self,
        ctx: Ctx,
        local_path: &str,
        remote_dir: &str,
    ) -> Result<String, String> {
        if local_path.trim().is_empty() {
            return Err("enter the full path of the file on this computer".into());
        }
        validate_remote(
            remote_dir,
            "enter the folder on the computer to upload into",
        )?;
        let src = PathBuf::from(local_path);
        let (_file, ident) = open_source(&src)?;
        let name = remote_file_name(&src)?;
        (ctx.creds)().await?;
        let id = new_id()?;
        let remote_path = join_remote(remote_dir, &name);
        let view = TransferView {
            id: id.clone(),
            direction: Direction::Upload,
            state: State::Queued,
            name,
            remote_path: remote_path.clone(),
            local_path: local_path.to_string(),
            done: 0,
            total: ident.size,
            error: String::new(),
            verified: false,
        };
        self.add(ctx, Kind::Upload { src, remote_path }, view);
        Ok(id)
    }

    fn add(&self, ctx: Ctx, kind: Kind, view: TransferView) {
        let (tx, rx) = watch::channel(false);
        let item = Arc::new(Item {
            view: Mutex::new(view),
            cancel: Mutex::new(tx),
            ctx,
            kind,
            resume: Mutex::new(Resume::default()),
        });
        lock(&self.inner.items).push(item.clone());
        tokio::spawn(run(self.inner.clone(), item, rx));
    }

    fn find(&self, id: &str) -> Result<Arc<Item>, String> {
        lock(&self.inner.items)
            .iter()
            .find(|i| lock(&i.view).id == id)
            .cloned()
            .ok_or_else(|| "no such transfer".to_string())
    }

    /// Every transfer, newest first.
    pub fn list(&self) -> Vec<TransferView> {
        lock(&self.inner.items)
            .iter()
            .rev()
            .map(|i| i.snapshot())
            .collect()
    }

    pub fn get(&self, id: &str) -> Option<TransferView> {
        self.find(id).ok().map(|i| i.snapshot())
    }

    /// Stops a waiting or running transfer, or gives up on a failed one. A download's part file
    /// and an upload's session on the computer are removed; a finished transfer is left alone.
    pub fn cancel(&self, id: &str) -> Result<(), String> {
        let item = self.find(id)?;
        let state = item.snapshot().state;
        match state {
            State::Queued | State::Running => {
                lock(&item.cancel).send_replace(true);
            }
            State::Failed => {
                item.update(|v| {
                    v.state = State::Cancelled;
                    v.error.clear();
                });
                discard_local(&item);
                if let Some(session) = lock(&item.resume).session.take() {
                    let item = item.clone();
                    tokio::spawn(async move {
                        if let Ok(conn) = (item.ctx.creds)().await {
                            delete_session(&conn, &session.id).await;
                        }
                    });
                }
            }
            State::Done | State::Cancelled => {}
        }
        Ok(())
    }

    /// Starts a failed or cancelled transfer again. A download continues from what it already has;
    /// an upload sends only the chunks the agent does not have.
    pub fn retry(&self, id: &str) -> Result<(), String> {
        let item = self.find(id)?;
        {
            let mut v = lock(&item.view);
            if !matches!(v.state, State::Failed | State::Cancelled) {
                return Err("that transfer cannot be retried now".into());
            }
            v.state = State::Queued;
            v.error.clear();
        }
        let (tx, rx) = watch::channel(false);
        *lock(&item.cancel) = tx;
        tokio::spawn(run(self.inner.clone(), item, rx));
        Ok(())
    }

    /// Removes finished and cancelled transfers from the list; failed ones stay until the user
    /// retries or cancels them. Returns how many were removed.
    pub fn clear_finished(&self) -> usize {
        let mut items = lock(&self.inner.items);
        let before = items.len();
        items.retain(|i| !matches!(lock(&i.view).state, State::Done | State::Cancelled));
        before - items.len()
    }
}

async fn wait_cancel(rx: &mut watch::Receiver<bool>) {
    if rx.wait_for(|stop| *stop).await.is_err() {
        // The sender is gone without a cancel: never end the transfer for that.
        std::future::pending::<()>().await;
    }
}

/// One attempt at a transfer, from waiting for a slot to its end state.
async fn run(inner: Arc<Inner>, item: Arc<Item>, mut cancel: watch::Receiver<bool>) {
    let slot = tokio::select! {
        s = inner.slots.clone().acquire_owned() => s.ok(),
        _ = wait_cancel(&mut cancel) => None,
    };
    let Some(_slot) = slot else {
        cleanup_cancelled(&item).await;
        return;
    };
    item.update(|v| {
        v.state = State::Running;
        v.error.clear();
    });
    let direction = item.snapshot().direction;
    let outcome = tokio::select! {
        r = work(&inner.opts, &item) => Some(r),
        _ = wait_cancel(&mut cancel) => None,
    };
    match outcome {
        Some(Ok(())) => {
            item.update(|v| v.state = State::Done);
            applog::info(&format!("{direction:?} finished"));
        }
        Some(Err(msg)) => {
            // The message can carry the request URL (with the remote path) or a local path; the log feeds the
            // diagnostics report, so it only records that the transfer failed. The window shows the message.
            applog::error(&format!("{direction:?} failed"));
            item.update(|v| {
                v.state = State::Failed;
                v.error = msg;
            });
        }
        None => cleanup_cancelled(&item).await,
    }
}

async fn work(opts: &Options, item: &Item) -> Result<(), String> {
    match &item.kind {
        Kind::Download { .. } => download(opts, item).await,
        Kind::Upload { .. } => upload(opts, item).await,
    }
}

fn discard_local(item: &Item) {
    if let Kind::Download { part, .. } = &item.kind {
        let _ = std::fs::remove_file(part);
    }
}

async fn cleanup_cancelled(item: &Item) {
    discard_local(item);
    let session = lock(&item.resume).session.take();
    if let Some(session) = session {
        if let Ok(conn) = (item.ctx.creds)().await {
            delete_session(&conn, &session.id).await;
        }
    }
    item.update(|v| {
        v.state = State::Cancelled;
        v.error.clear();
    });
    applog::info("transfer cancelled");
}

/// Best effort: the agent forgets an upload session that nobody touches for a week anyway.
async fn delete_session(conn: &Conn, id: &str) {
    let Ok(client) = AgentClient::pinned(&conn.host, &conn.fingerprint) else {
        return;
    };
    let (http, base) = client.transport();
    // A chunk the agent is still reading holds the session for a moment; wait it out.
    for _ in 0..8 {
        let sent = http
            .delete(format!("{base}/transfers/{id}"))
            .bearer_auth(&conn.token)
            .header("X-RFE-Client-Version", CLIENT_VERSION)
            .timeout(Duration::from_secs(10))
            .send()
            .await;
        match sent {
            Ok(r) if r.status().as_u16() == 409 => {
                tokio::time::sleep(Duration::from_millis(250)).await
            }
            _ => return,
        }
    }
}

// ---- messages ----

/// Agent error codes this module words for transfers. A code listed here is shown with this text
/// instead of the generic one (a refusal to upload is not about managing devices).
pub const TRANSFER_CODES: &[&str] = &[
    "PATH_NOT_FOUND",
    "FORBIDDEN",
    "READ_ONLY",
    "CAPABILITY_DENIED",
    "CONFLICT",
    "HASH_MISMATCH",
    "CHUNK_HASH_MISMATCH",
    "PAYLOAD_TOO_LARGE",
    "RESOURCE_LIMIT",
    "TRANSFER_ACTIVE",
    "TRANSFER_NOT_OPEN",
];

pub fn transfer_message(code: &str) -> Option<&'static str> {
    Some(match code {
        "PATH_NOT_FOUND" => {
            "The computer has no file at that path. It may have been moved or deleted."
        }
        "FORBIDDEN" => {
            "This login may not use that path on the computer. It is outside the folders it can reach."
        }
        "READ_ONLY" => "The agent or this device is read-only, so it cannot accept uploads.",
        "CAPABILITY_DENIED" => {
            "This device has not been allowed to do that. Allow it on the computer, in the device's access settings."
        }
        "CONFLICT" => "A file with this name already exists on the computer.",
        "HASH_MISMATCH" => {
            "The file changed or was damaged while it was uploading. The upload was discarded; try again."
        }
        "CHUNK_HASH_MISMATCH" => {
            "A piece of the file was damaged in transit three times in a row. Try again."
        }
        "PAYLOAD_TOO_LARGE" => "The file is too large for the computer to accept.",
        "RESOURCE_LIMIT" => {
            "The computer has too many uploads open. Wait for one to finish, then retry."
        }
        "TRANSFER_ACTIVE" => {
            "The computer is still finishing the previous attempt. Retry in a moment."
        }
        "TRANSFER_NOT_OPEN" => {
            "The computer closed this upload. Retry starts it again from the beginning."
        }
        _ => return None,
    })
}

fn describe(e: &AgentError) -> String {
    if let AgentError::Server { code, .. } = e {
        if let Some(text) = transfer_message(code) {
            return text.to_string();
        }
    }
    e.to_string()
}

fn net(e: reqwest::Error) -> String {
    describe(&network_error(e))
}

async fn refused(resp: reqwest::Response) -> String {
    describe(&response_error(resp).await)
}

// ---- names and paths ----

/// The remote path as the agent will receive it, checked only for what could break the request.
fn validate_remote(path: &str, empty: &str) -> Result<(), String> {
    if path.trim().is_empty() {
        return Err(empty.to_string());
    }
    if path.contains('\0') || path.len() > MAX_REMOTE_PATH {
        return Err("that path on the computer is not usable".into());
    }
    Ok(())
}

fn is_invisible(c: char) -> bool {
    matches!(c,
        '\u{200b}'..='\u{200f}' | '\u{202a}'..='\u{202e}' | '\u{2060}'..='\u{2064}'
        | '\u{2066}'..='\u{2069}' | '\u{feff}')
}

/// A file name that is safe to create in the downloads folder, from whatever the remote path says:
/// only the last component (split on `/` and `\`), no control or direction-changing characters, no
/// leading dots (no hidden files, no `..`) and no trailing dots or spaces, at most 200 bytes with the
/// extension kept. Never empty.
pub fn safe_name(remote_path: &str) -> String {
    let last = remote_path
        .rsplit(['/', '\\'])
        .find(|s| !s.is_empty())
        .unwrap_or("");
    let cleaned: String = last
        .chars()
        .filter(|c| !c.is_control() && !is_invisible(*c))
        .collect();
    let trimmed = cleaned.trim_matches(|c: char| c == '.' || c.is_whitespace());
    if trimmed.is_empty() {
        return "download".to_string();
    }
    if trimmed.len() <= 200 {
        return trimmed.to_string();
    }
    let (stem, ext) = split_ext(trimmed);
    let keep = 200usize.saturating_sub(ext.len()).max(1);
    let mut end = keep.min(stem.len());
    while !stem.is_char_boundary(end) {
        end -= 1;
    }
    let short = stem[..end].trim_end_matches(|c: char| c == '.' || c.is_whitespace());
    format!("{}{ext}", if short.is_empty() { "download" } else { short })
}

fn split_ext(name: &str) -> (&str, &str) {
    match name.rfind('.') {
        Some(i) if i > 0 && name.len() - i <= 16 => (&name[..i], &name[i..]),
        _ => (name, ""),
    }
}

/// The `n`th candidate for `name`: itself, then `name (1)`, `name (2)` with the extension kept last.
pub fn numbered_name(name: &str, n: u32) -> String {
    if n == 0 {
        return name.to_string();
    }
    let (stem, ext) = split_ext(name);
    format!("{stem} ({n}){ext}")
}

/// Puts the finished part file at `dir/name`, or at `dir/name (1)` and so on if that is taken. The
/// file under its final name is created by a hard link (or an exclusive create when the file system
/// has no links), both of which fail instead of replacing what is there, so a file that appears
/// while the download runs is never overwritten. The part file is removed afterwards.
pub fn publish_no_clobber(part: &Path, dir: &Path, name: &str) -> std::io::Result<PathBuf> {
    for n in 0..10_000u32 {
        let target = dir.join(numbered_name(name, n));
        match std::fs::hard_link(part, &target) {
            Ok(()) => {
                let _ = std::fs::remove_file(part);
                return Ok(target);
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(_) => match copy_exclusive(part, &target) {
                Ok(()) => {
                    let _ = std::fs::remove_file(part);
                    return Ok(target);
                }
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(e),
            },
        }
    }
    Err(std::io::Error::new(
        std::io::ErrorKind::AlreadyExists,
        "every numbered name is taken",
    ))
}

fn copy_exclusive(from: &Path, to: &Path) -> std::io::Result<()> {
    let mut src = File::open(from)?;
    let mut dst = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(to)?;
    let copied = std::io::copy(&mut src, &mut dst).and_then(|_| dst.sync_all());
    if let Err(e) = copied {
        drop(dst);
        let _ = std::fs::remove_file(to);
        return Err(e);
    }
    Ok(())
}

/// The name an uploaded file gets on the computer: its own name without separators or control
/// characters. (Dot files are fine there; only the download side hides nothing from the user.)
fn remote_file_name(src: &Path) -> Result<String, String> {
    let raw = src
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let cleaned: String = raw
        .chars()
        .filter(|c| !c.is_control() && !is_invisible(*c))
        .map(|c| if c == '/' || c == '\\' { '_' } else { c })
        .collect();
    let cleaned = cleaned.trim().to_string();
    if cleaned.is_empty() || cleaned == "." || cleaned == ".." {
        return Err("that is not a regular file".into());
    }
    Ok(cleaned)
}

/// `dir` and `name` joined with the separator `dir` itself uses (a Windows agent's `C:\Users\me`
/// gets a backslash), without doubling a trailing one.
pub fn join_remote(dir: &str, name: &str) -> String {
    let sep = if dir.contains('\\') && !dir.contains('/') {
        '\\'
    } else {
        '/'
    };
    let trimmed = dir.trim_end_matches(['/', '\\']);
    format!("{trimmed}{sep}{name}")
}

// ---- local files ----

fn new_id() -> Result<String, String> {
    let mut b = [0u8; 8];
    getrandom::getrandom(&mut b).map_err(|e| format!("random: {e}"))?;
    Ok(format!("t{}", hex::encode(b)))
}

fn ident_of(m: &std::fs::Metadata) -> Ident {
    #[cfg(unix)]
    let id = {
        use std::os::unix::fs::MetadataExt;
        (m.dev(), m.ino())
    };
    #[cfg(not(unix))]
    let id = (0, 0);
    Ident {
        size: m.len(),
        mtime: m.modified().ok(),
        id,
    }
}

/// Opens the file the user typed, if it is a regular file. The path must be absolute and its last
/// component must not be a symbolic link: a link is refused, never followed, so what is read is
/// what the user typed. The opened file is compared with what was checked, so a swap in between is
/// caught.
fn open_source(path: &Path) -> Result<(File, Ident), String> {
    if !path.is_absolute() {
        return Err("give the full path of the file, starting with /".into());
    }
    let read_error = |e: std::io::Error| format!("cannot read that file: {e}");
    let checked = std::fs::symlink_metadata(path).map_err(read_error)?;
    if checked.file_type().is_symlink() {
        return Err("that path is a symbolic link; type the real path of the file".into());
    }
    if !checked.is_file() {
        return Err("that is not a regular file".into());
    }
    let file = File::open(path).map_err(read_error)?;
    let opened = file.metadata().map_err(read_error)?;
    if !opened.is_file() || ident_of(&opened).id != ident_of(&checked).id {
        return Err("the file changed while it was being opened; try again".into());
    }
    Ok((file, ident_of(&opened)))
}

fn read_exact_at(file: &File, buf: &mut [u8], offset: u64) -> std::io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::FileExt;
        file.read_exact_at(buf, offset)
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::FileExt;
        let mut done = 0;
        while done < buf.len() {
            let n = file.seek_read(&mut buf[done..], offset + done as u64)?;
            if n == 0 {
                return Err(std::io::ErrorKind::UnexpectedEof.into());
            }
            done += n;
        }
        Ok(())
    }
}

fn hash_reader(mut r: impl Read) -> std::io::Result<String> {
    let mut h = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = r.read(&mut buf)?;
        if n == 0 {
            return Ok(hex::encode(h.finalize()));
        }
        h.update(&buf[..n]);
    }
}

fn hash_file_at(file: &File, size: u64) -> std::io::Result<String> {
    let mut h = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    let mut at = 0u64;
    while at < size {
        let n = ((size - at) as usize).min(buf.len());
        read_exact_at(file, &mut buf[..n], at)?;
        h.update(&buf[..n]);
        at += n as u64;
    }
    Ok(hex::encode(h.finalize()))
}

async fn blocking<T: Send + 'static>(
    f: impl FnOnce() -> Result<T, String> + Send + 'static,
) -> Result<T, String> {
    tokio::task::spawn_blocking(f)
        .await
        .map_err(|e| format!("a background task failed: {e}"))?
}

fn client_for(conn: &Conn) -> Result<AgentClient, String> {
    AgentClient::pinned(&conn.host, &conn.fingerprint).map_err(|e| describe(&e))
}

// ---- download ----

/// `(first, last, total)` from `Content-Range: bytes first-last/total`.
fn parse_content_range(h: &reqwest::header::HeaderMap) -> Option<(u64, u64, u64)> {
    let v = h
        .get("content-range")?
        .to_str()
        .ok()?
        .strip_prefix("bytes ")?;
    let (range, total) = v.split_once('/')?;
    let (a, b) = range.split_once('-')?;
    let (a, b, total) = (a.parse().ok()?, b.parse().ok()?, total.parse().ok()?);
    (a <= b && b < total).then_some((a, b, total))
}

/// The total from an unsatisfiable range's `Content-Range: bytes */total`.
fn parse_unsatisfied(h: &reqwest::header::HeaderMap) -> Option<u64> {
    h.get("content-range")?
        .to_str()
        .ok()?
        .strip_prefix("bytes */")?
        .parse()
        .ok()
}

fn open_part(part: &Path, truncate: bool) -> Result<File, String> {
    let mut o = std::fs::OpenOptions::new();
    o.write(true).create(true);
    if truncate {
        o.truncate(true);
    } else {
        o.append(true);
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        o.mode(0o600);
    }
    o.open(part)
        .map_err(|e| format!("cannot write {}: {e}", part.display()))
}

fn part_len(part: &Path) -> Result<u64, String> {
    match std::fs::metadata(part) {
        Ok(m) => Ok(m.len()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(0),
        Err(e) => Err(format!("cannot read {}: {e}", part.display())),
    }
}

/// Writes a response body to the part file as it arrives, so a dropped connection keeps what came.
async fn append_body(
    mut resp: reqwest::Response,
    part: &Path,
    truncate: bool,
    expect: u64,
    from: u64,
    total: u64,
    item: &Item,
) -> Result<(), String> {
    let mut file = open_part(part, truncate)?;
    let mut written = 0u64;
    while let Some(chunk) = resp.chunk().await.map_err(net)? {
        file.write_all(&chunk)
            .map_err(|e| format!("cannot write {}: {e}", part.display()))?;
        written += chunk.len() as u64;
        if written > expect {
            return Err("unexpected response: the agent sent more than was asked for".into());
        }
        item.set_progress(from + written, total);
    }
    file.flush()
        .map_err(|e| format!("cannot write {}: {e}", part.display()))?;
    if written != expect {
        return Err("the agent ended the download early".into());
    }
    Ok(())
}

async fn remote_checksum(
    http: &reqwest::Client,
    base: &str,
    conn: &Conn,
    path: &str,
) -> Option<String> {
    #[derive(Deserialize)]
    struct Sum {
        checksum: String,
    }
    let resp = http
        .get(format!("{base}/fs/checksum"))
        .query(&[("path", path), ("algo", "sha256")])
        .bearer_auth(&conn.token)
        .header("X-RFE-Client-Version", CLIENT_VERSION)
        .timeout(HASH_TIMEOUT)
        .send()
        .await
        .ok()?;
    if !resp.status().is_success() {
        return None;
    }
    resp.json::<Sum>().await.ok().map(|s| s.checksum)
}

async fn download(opts: &Options, item: &Item) -> Result<(), String> {
    let Kind::Download { part, name } = &item.kind else {
        return Err("internal: not a download".into());
    };
    let conn = (item.ctx.creds)().await?;
    let client = client_for(&conn)?;
    let (http, base) = client.transport();
    let remote = item.snapshot().remote_path;
    let segment = opts.segment_size.max(1);

    let mut total: Option<u64> = None;
    let mut restarted = false;
    loop {
        let offset = part_len(part)?;
        if total.is_some_and(|t| offset >= t) {
            break;
        }
        let resp = http
            .get(format!("{base}/content"))
            .query(&[("path", remote.as_str())])
            .bearer_auth(&conn.token)
            .header("X-RFE-Client-Version", CLIENT_VERSION)
            .header("Range", format!("bytes={offset}-{}", offset + segment - 1))
            // A gzip body would not line up with byte offsets; a ranged request is never gzipped,
            // and this keeps the first one honest too.
            .header("Accept-Encoding", "identity")
            .timeout(SEGMENT_TIMEOUT)
            .send()
            .await
            .map_err(net)?;
        match resp.status().as_u16() {
            206 => {
                let (first, last, size) = parse_content_range(resp.headers())
                    .ok_or("unexpected response: the agent sent a range this app cannot read")?;
                if first != offset {
                    return Err("unexpected response: the agent sent a different range".into());
                }
                total = Some(size);
                item.set_progress(offset, size);
                append_body(resp, part, false, last - first + 1, offset, size, item).await?;
            }
            200 => {
                // The agent ignored the range: it sent the whole file (an empty one, always).
                let size = resp
                    .content_length()
                    .ok_or("unexpected response: no length")?;
                total = Some(size);
                item.set_progress(0, size);
                append_body(resp, part, true, size, 0, size, item).await?;
                if size == 0 {
                    break;
                }
            }
            416 => match parse_unsatisfied(resp.headers()) {
                Some(size) if size == offset => {
                    total = Some(size);
                }
                // The part is longer than the file now: it belongs to an older version.
                Some(size) if offset > size && !restarted => {
                    restarted = true;
                    drop(open_part(part, true)?);
                }
                _ => return Err("unexpected response: the agent refused the range".into()),
            },
            _ => return Err(refused(resp).await),
        }
    }

    // Whole. Compare with what the agent has before the file gets a real name.
    let size = total.unwrap_or(0);
    item.set_progress(size, size);
    let local = {
        let part = part.clone();
        blocking(move || {
            File::open(&part)
                .and_then(hash_reader)
                .map_err(|e| format!("cannot read {}: {e}", part.display()))
        })
        .await?
    };
    let verified = match remote_checksum(http, base, &conn, &remote).await {
        Some(sum) if sum.eq_ignore_ascii_case(&local) => true,
        Some(_) => {
            let _ = std::fs::remove_file(part);
            return Err("The downloaded copy does not match the file on the computer. It was discarded; start it again.".into());
        }
        None => false,
    };
    let (part, dir, name) = (part.clone(), item.ctx.download_dir.clone(), name.clone());
    let final_path = blocking(move || {
        publish_no_clobber(&part, &dir, &name)
            .map_err(|e| format!("the downloaded file could not be put in place: {e}"))
    })
    .await?;
    item.update(|v| {
        v.name = final_path
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        v.local_path = final_path.display().to_string();
        v.verified = verified;
    });
    Ok(())
}

// ---- upload ----

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct SessionBody {
    id: String,
    chunk_size: usize,
    total_chunks: usize,
    received_chunks: Vec<usize>,
    status: String,
}

fn bad_session(b: &SessionBody) -> bool {
    b.id.is_empty()
        || b.id
            .contains(|c: char| !(c.is_ascii_alphanumeric() || c == '-' || c == '_'))
        || b.chunk_size == 0
        || b.chunk_size > MAX_SESSION_CHUNK
        || b.total_chunks == 0
}

fn authed(rb: reqwest::RequestBuilder, conn: &Conn) -> reqwest::RequestBuilder {
    rb.bearer_auth(&conn.token)
        .header("X-RFE-Client-Version", CLIENT_VERSION)
}

async fn upload(opts: &Options, item: &Item) -> Result<(), String> {
    let Kind::Upload { src, remote_path } = &item.kind else {
        return Err("internal: not an upload".into());
    };
    let conn = (item.ctx.creds)().await?;
    let client = client_for(&conn)?;
    let (http, base) = client.transport();

    let (file, ident) = open_source(src)?;
    let file = Arc::new(file);
    let size = ident.size;
    item.set_progress(0, size);

    // Is the session from an earlier attempt still good, and for the same file?
    let saved = {
        let r = lock(&item.resume);
        match (&r.session, &r.ident) {
            (Some(s), Some(i)) if *i == ident => Some(s.clone()),
            _ => None,
        }
    };
    let mut have: HashSet<usize> = HashSet::new();
    let mut session = None;
    if let Some(s) = saved {
        let resp = authed(http.get(format!("{base}/transfers/{}", s.id)), &conn)
            .timeout(Duration::from_secs(30))
            .send()
            .await
            .map_err(net)?;
        match resp.status().as_u16() {
            200 => {
                let body: SessionBody = resp
                    .json()
                    .await
                    .map_err(|e| format!("unexpected response: {e}"))?;
                match body.status.as_str() {
                    "open" => {
                        have = body.received_chunks.into_iter().collect();
                        session = Some(s);
                    }
                    "completed" => {
                        lock(&item.resume).session = None;
                        item.set_progress(size, size);
                        item.update(|v| v.verified = true);
                        return Ok(());
                    }
                    _ => {}
                }
            }
            404 => {}
            _ => return Err(refused(resp).await),
        }
    }

    let session = match session {
        Some(s) => s,
        None => {
            lock(&item.resume).session = None;
            item.set_progress(0, size);
            let sha256 = {
                let file = file.clone();
                blocking(move || {
                    hash_file_at(&file, size).map_err(|e| format!("cannot read that file: {e}"))
                })
                .await?
            };
            let resp = authed(http.post(format!("{base}/transfers")), &conn)
                .json(&serde_json::json!({
                    "path": remote_path,
                    "size": size,
                    "sha256": sha256,
                    "chunkSize": opts.chunk_size,
                    "overwrite": false,
                }))
                .timeout(Duration::from_secs(60))
                .send()
                .await
                .map_err(net)?;
            if resp.status().as_u16() != 201 {
                return Err(refused(resp).await);
            }
            let body: SessionBody = resp
                .json()
                .await
                .map_err(|e| format!("unexpected response: {e}"))?;
            if bad_session(&body) {
                return Err(
                    "unexpected response: the agent sent a session this app cannot use".into(),
                );
            }
            let s = Session {
                id: body.id,
                chunk_size: body.chunk_size,
                total_chunks: body.total_chunks,
            };
            let mut r = lock(&item.resume);
            r.session = Some(s.clone());
            r.ident = Some(ident.clone());
            s
        }
    };

    let chunk_len = |n: usize| -> u64 {
        let start = n as u64 * session.chunk_size as u64;
        size.saturating_sub(start).min(session.chunk_size as u64)
    };
    let mut sent: u64 = have.iter().map(|&n| chunk_len(n)).sum();
    item.set_progress(sent, size);

    for n in 0..session.total_chunks {
        if have.contains(&n) {
            continue;
        }
        let len = chunk_len(n) as usize;
        let (data, sum) = {
            let file = file.clone();
            let at = n as u64 * session.chunk_size as u64;
            blocking(move || {
                let mut buf = vec![0u8; len];
                read_exact_at(&file, &mut buf, at)
                    .map_err(|e| format!("cannot read that file: {e}"))?;
                let sum = hex::encode(Sha256::digest(&buf));
                Ok((buf, sum))
            })
            .await?
        };
        let mut damaged = 0;
        loop {
            let resp = authed(
                http.put(format!("{base}/transfers/{}/chunks/{n}", session.id)),
                &conn,
            )
            .header("X-Chunk-Sha256", &sum)
            .header("Content-Type", "application/octet-stream")
            .body(data.clone())
            .timeout(CHUNK_TIMEOUT)
            .send()
            .await
            .map_err(net)?;
            match resp.status().as_u16() {
                204 => break,
                409 if damaged < 2 => {
                    let e = response_error(resp).await;
                    if matches!(&e, AgentError::Server { code, .. } if code == "CHUNK_HASH_MISMATCH")
                    {
                        damaged += 1;
                        continue;
                    }
                    return Err(describe(&e));
                }
                _ => return Err(refused(resp).await),
            }
        }
        sent += len as u64;
        item.set_progress(sent, size);
    }

    // Every chunk is there: the agent hashes the whole file and renames it into place.
    item.set_progress(size, size);
    let resp = authed(
        http.post(format!("{base}/transfers/{}/complete", session.id)),
        &conn,
    )
    .timeout(HASH_TIMEOUT)
    .send()
    .await
    .map_err(net)?;
    if !resp.status().is_success() {
        let e = response_error(resp).await;
        if matches!(&e, AgentError::Server { code, .. } if code == "HASH_MISMATCH" || code == "TRANSFER_NOT_OPEN")
        {
            // The agent closed this session; the next attempt must open a new one.
            lock(&item.resume).session = None;
        }
        return Err(describe(&e));
    }
    #[derive(Deserialize, Default)]
    #[serde(default)]
    struct Done {
        verified: bool,
    }
    let done: Done = resp.json().await.unwrap_or_default();
    lock(&item.resume).session = None;
    item.update(|v| v.verified = done.verified);
    Ok(())
}

// ---- the app's side: credentials and the downloads folder ----

/// The folder every download goes to: the user's download folder (the XDG one on Linux) plus
/// `RFE Desktop`. Fixed: no command takes a destination.
pub fn download_folder(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    use tauri::Manager;
    let paths = app.path();
    let base = paths
        .download_dir()
        .or_else(|_| paths.home_dir().map(|h| h.join("Downloads")))
        .map_err(|_| "cannot find your Downloads folder".to_string())?;
    Ok(base.join(FOLDER_NAME))
}

/// Credentials from the saved login: the keystore holds the token, `state.json` the agent's address
/// and the certificate the user trusted.
pub fn saved_login(data_dir: PathBuf) -> Creds {
    use crate::secrets::{Offloaded, OsKeystore};
    Arc::new(move || {
        let dir = data_dir.clone();
        Box::pin(async move {
            let saved = Offloaded::new(OsKeystore::new())
                .run(move |s| crate::flows::load_saved(&dir, s))
                .await?;
            if saved.token.is_empty() || saved.host.is_empty() {
                return Err("not signed in".to_string());
            }
            Ok(Conn {
                host: saved.host,
                fingerprint: saved.fingerprint,
                token: saved.token,
            })
        })
    })
}

fn app_ctx(app: &tauri::AppHandle) -> Result<Ctx, String> {
    use tauri::Manager;
    let data_dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
    Ok(Ctx {
        creds: saved_login(data_dir),
        download_dir: download_folder(app)?,
    })
}

#[tauri::command]
pub async fn transfer_download(
    app: tauri::AppHandle,
    state: tauri::State<'_, Transfers>,
    remote_path: String,
) -> Result<String, String> {
    state.start_download(app_ctx(&app)?, &remote_path).await
}

#[tauri::command]
pub async fn transfer_upload(
    app: tauri::AppHandle,
    state: tauri::State<'_, Transfers>,
    local_path: String,
    remote_dir: String,
) -> Result<String, String> {
    state
        .start_upload(app_ctx(&app)?, &local_path, &remote_dir)
        .await
}

#[tauri::command]
pub async fn transfer_list(
    state: tauri::State<'_, Transfers>,
) -> Result<Vec<TransferView>, String> {
    Ok(state.list())
}

#[tauri::command]
pub async fn transfer_cancel(state: tauri::State<'_, Transfers>, id: String) -> Result<(), String> {
    state.cancel(&id)
}

#[tauri::command]
pub async fn transfer_retry(state: tauri::State<'_, Transfers>, id: String) -> Result<(), String> {
    state.retry(&id)
}

#[tauri::command]
pub async fn transfer_clear_finished(state: tauri::State<'_, Transfers>) -> Result<usize, String> {
    Ok(state.clear_finished())
}

/// Where downloads go, for the screen to show.
#[tauri::command]
pub async fn transfer_folder(app: tauri::AppHandle) -> Result<String, String> {
    Ok(download_folder(&app)?.display().to_string())
}
