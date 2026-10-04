//! App-level flows shared by the Tauri commands and the integration tests.

use crate::agent_client::{
    capture_fingerprint, match_code, new_client_nonce, normalize_fingerprint, AgentClient,
    AgentError, Device, LoginOk, PairPoll,
};
use crate::fsutil::write_private;
use crate::identity::Identity;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::Path;

use crate::secrets::{account, Offloaded, SecretStore};

#[derive(Debug, Clone, Default)]
pub struct Saved {
    pub host: String,
    pub fingerprint: String,
    /// Lives in the OS keystore, never in `state.json`.
    pub token: String,
    pub username: String,
    /// The agent-assigned id of this computer's device row.
    pub device_id: String,
}

/// What `state.json` holds: no secrets. `token` is read only to migrate a pre-keystore file
/// and is never written.
#[derive(Default, Serialize, Deserialize)]
struct StateFile {
    #[serde(default)]
    host: String,
    #[serde(default)]
    fingerprint: String,
    #[serde(default)]
    username: String,
    #[serde(default)]
    device_id: String,
    #[serde(default, skip_serializing)]
    token: String,
    /// Every certificate the user has trusted, by `pin_key`. `None` only for a file written before
    /// pins were kept per address; `read_state` folds that file's single host into it.
    #[serde(default)]
    pins: Option<BTreeMap<String, String>>,
}

/// The key a pin is stored under: the address as `host:port`, case-folded. The same host on
/// another port is another agent and has its own pin.
pub fn pin_key(host: &str) -> String {
    host.trim().to_ascii_lowercase()
}

impl StateFile {
    fn pins(&self) -> &BTreeMap<String, String> {
        static NONE: BTreeMap<String, String> = BTreeMap::new();
        self.pins.as_ref().unwrap_or(&NONE)
    }

    fn pins_mut(&mut self) -> &mut BTreeMap<String, String> {
        self.pins.get_or_insert_with(BTreeMap::new)
    }
}

impl StateFile {
    fn into_saved(self, token: String) -> Saved {
        Saved {
            host: self.host,
            fingerprint: self.fingerprint,
            username: self.username,
            device_id: self.device_id,
            token,
        }
    }
}

fn state_path(dir: &Path) -> std::path::PathBuf {
    dir.join("state.json")
}

/// Missing file means "never configured". Any other read or parse failure is an
/// error, so a damaged state file cannot silently drop the pin and token.
fn read_state(dir: &Path) -> Result<StateFile, String> {
    let path = state_path(dir);
    match std::fs::read(&path) {
        Ok(bytes) => {
            let mut f: StateFile = serde_json::from_slice(&bytes).map_err(|e| {
                format!(
                    "{} is damaged ({e}); delete it to start over",
                    path.display()
                )
            })?;
            if f.pins.is_none() {
                let legacy = (!f.host.is_empty() && !f.fingerprint.is_empty())
                    .then(|| (pin_key(&f.host), f.fingerprint.clone()));
                f.pins = Some(legacy.into_iter().collect());
            }
            Ok(f)
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(StateFile::default()),
        Err(e) => Err(format!("read {}: {e}", path.display())),
    }
}

fn write_state(dir: &Path, f: &StateFile) -> Result<(), String> {
    let json = serde_json::to_vec_pretty(f).map_err(|e| e.to_string())?;
    write_private(&state_path(dir), &json)
}

/// Loads the saved state and the token from the keystore. A token left in `state.json` by an
/// earlier version is moved into the keystore first, then removed from the file; if the
/// keystore refuses, this fails and the file is left as it was.
pub fn load_saved(dir: &Path, store: &dyn SecretStore) -> Result<Saved, String> {
    let mut f = read_state(dir)?;
    let acct = account("token", dir);
    if !f.token.is_empty() {
        store.set(&acct, &f.token)?;
        if store.get(&acct)?.as_deref() != Some(f.token.as_str()) {
            return Err("the OS keystore did not keep the login token".into());
        }
        f.token.clear();
        write_state(dir, &f)?;
    }
    let token = store.get(&acct)?.unwrap_or_default();
    Ok(f.into_saved(token))
}

/// Stores the token in the keystore (or deletes it when empty), then the rest in `state.json`.
pub fn save(dir: &Path, store: &dyn SecretStore, s: &Saved) -> Result<(), String> {
    let acct = account("token", dir);
    if s.token.is_empty() {
        store.delete(&acct)?;
    } else {
        store.set(&acct, &s.token)?;
    }
    // Keep every other trusted address; this session's address is trusted at this fingerprint.
    let mut f = read_state(dir)?;
    if !s.host.is_empty() && !s.fingerprint.is_empty() {
        f.pins_mut().insert(pin_key(&s.host), s.fingerprint.clone());
    }
    f.host = s.host.clone();
    f.fingerprint = s.fingerprint.clone();
    f.username = s.username.clone();
    f.device_id = s.device_id.clone();
    f.token.clear();
    write_state(dir, &f)
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Probe {
    pub fingerprint: String,
    /// The fingerprint trusted earlier for this same address, or empty.
    pub previous: String,
    /// True when `previous` is set and differs from what the agent presents now.
    pub changed: bool,
}

pub async fn probe(dir: &Path, host: &str) -> Result<Probe, AgentError> {
    let saved = read_state(dir).map_err(AgentError::Local)?;
    let fingerprint = capture_fingerprint(host).await?;
    let previous = saved
        .pins()
        .get(&pin_key(host))
        .cloned()
        .unwrap_or_default();
    let changed = !previous.is_empty() && previous != fingerprint;
    Ok(Probe {
        fingerprint,
        previous,
        changed,
    })
}

/// Loads or creates this computer's device key. Runs before any network traffic, so a missing or
/// locked keystore stops enrollment before the agent sees anything.
async fn device_identity(dir: &Path, store: &Offloaded) -> Result<Identity, AgentError> {
    let dir = dir.to_path_buf();
    store
        .run(move |s| Identity::load_or_create(&dir, s))
        .await
        .map_err(AgentError::Local)
}

/// Stores what an enrollment returned: the pin and device id in `state.json`, the token in the
/// keystore.
async fn remember(
    dir: &Path,
    host: &str,
    fingerprint: &str,
    username: &str,
    ok: LoginOk,
    store: &Offloaded,
) -> Result<Saved, AgentError> {
    let saved = Saved {
        host: host.to_string(),
        fingerprint: normalize_fingerprint(fingerprint),
        token: ok.device_token,
        username: username.to_string(),
        device_id: ok.device_id,
    };
    let (dir, to_save) = (dir.to_path_buf(), saved.clone());
    store
        .run(move |s| save(&dir, s, &to_save))
        .await
        .map_err(AgentError::Local)?;
    Ok(saved)
}

/// Pins `fingerprint` (the one the user confirmed), logs in, and stores the pin and token.
pub async fn login(
    dir: &Path,
    host: &str,
    fingerprint: &str,
    username: &str,
    password: &str,
    label: &str,
    store: &Offloaded,
) -> Result<Saved, AgentError> {
    let identity = device_identity(dir, store).await?;
    let client = AgentClient::pinned(host, fingerprint)?;
    let ok = client.login(&identity, username, password, label).await?;
    remember(dir, host, fingerprint, username, ok, store).await
}

/// Pins `fingerprint`, enrolls with a one-time pairing code, and stores the pin and token. The
/// result is an ordinary device (no account name), which the agent lets list and manage only itself.
pub async fn pair(
    dir: &Path,
    host: &str,
    fingerprint: &str,
    code: &str,
    label: &str,
    store: &Offloaded,
) -> Result<Saved, AgentError> {
    let code = code.trim();
    if code.is_empty() {
        return Err(AgentError::Local("enter the pairing code".into()));
    }
    let identity = device_identity(dir, store).await?;
    let client = AgentClient::pinned(host, fingerprint)?;
    let ok = client.pair(&identity, code, label).await?;
    remember(dir, host, fingerprint, "", ok, store).await
}

/// The first agent release that has `POST /pair/request`.
pub const MIN_AGENT_FOR_APPROVAL: &str = "agent-v1.43.0-rc.1";

/// A pairing request waiting for the owner to answer at the PC. `client_nonce` is the secret that
/// authorises polling, so it stays on the Rust side and is not part of what the window sees.
#[derive(Debug, Clone)]
pub struct PairWait {
    pub host: String,
    pub fingerprint: String,
    pub request_id: String,
    pub client_nonce: String,
    /// What the owner must see on the PC too, before approving.
    pub match_code: String,
    pub expires_in_seconds: u64,
}

/// Asks the agent to have the owner approve this computer at the PC. Nothing is stored until
/// the owner approves; the returned match code is for the user to compare with the PC.
pub async fn request_pairing(
    dir: &Path,
    host: &str,
    fingerprint: &str,
    label: &str,
    store: &Offloaded,
) -> Result<PairWait, AgentError> {
    let identity = device_identity(dir, store).await?;
    let client = AgentClient::pinned(host, fingerprint)?;
    let client_nonce = new_client_nonce()?;
    let started = client
        .pair_request(&identity, label, &client_nonce)
        .await
        .map_err(|e| match e {
            // An agent without the endpoint answers a bare-text 404, not the JSON error body.
            AgentError::Server { status: 404, code, .. } if code.starts_with("HTTP_") => {
                AgentError::Local(format!(
                    "This agent is too old to approve a new computer from the PC (it needs {MIN_AGENT_FOR_APPROVAL} or newer). \
                     Pair with a code or sign in with an account instead."
                ))
            }
            other => other,
        })?;
    let fingerprint = normalize_fingerprint(fingerprint);
    Ok(PairWait {
        match_code: match_code(&fingerprint, &client_nonce, &started.request_id)?,
        host: host.to_string(),
        fingerprint,
        request_id: started.request_id,
        client_nonce,
        expires_in_seconds: started.expires_in_seconds,
    })
}

#[derive(Debug)]
pub enum PairProgress {
    Pending,
    Rejected,
    /// The request is gone: it expired, or its approval was already collected.
    Expired,
    Approved(Saved),
}

/// Checks the request once. On approval the token is stored right away, because the agent hands
/// it out only once: if storing fails the approval is lost and the user must ask again.
pub async fn poll_pairing(
    dir: &Path,
    wait: &PairWait,
    store: &Offloaded,
) -> Result<PairProgress, AgentError> {
    let client = AgentClient::pinned(&wait.host, &wait.fingerprint)?;
    match client
        .poll_pair_request(&wait.request_id, &wait.client_nonce)
        .await
    {
        Ok(PairPoll::Pending) => Ok(PairProgress::Pending),
        Ok(PairPoll::Rejected) => Ok(PairProgress::Rejected),
        Ok(PairPoll::Approved(ok)) => {
            match remember(dir, &wait.host, &wait.fingerprint, "", ok, store).await {
                Ok(saved) => Ok(PairProgress::Approved(saved)),
                Err(e) => Err(AgentError::Local(format!(
                    "The PC approved this computer, but saving the login failed ({e}). The \
                     approval can be collected only once and is now used up. Ask again."
                ))),
            }
        }
        Err(AgentError::Server { status: 404, .. }) => Ok(PairProgress::Expired),
        Err(e) => Err(e),
    }
}

pub async fn list_devices(dir: &Path, store: &Offloaded) -> Result<Vec<Device>, AgentError> {
    let s = {
        let dir = dir.to_path_buf();
        store
            .run(move |s| load_saved(&dir, s))
            .await
            .map_err(AgentError::Local)?
    };
    if s.token.is_empty() || s.host.is_empty() {
        return Err(AgentError::Local("not signed in".into()));
    }
    // The pin map is the record of what is trusted: a forgotten pin ends the session here.
    let pinned = read_state(dir)
        .map_err(AgentError::Local)?
        .pins()
        .get(&pin_key(&s.host))
        .cloned()
        .ok_or_else(|| {
            AgentError::Local(format!(
                "{} is no longer a trusted agent; connect and compare its fingerprint again",
                s.host
            ))
        })?;
    let listed = AgentClient::pinned(&s.host, &pinned)?
        .devices(&s.token)
        .await;
    if let Err(AgentError::Server { status: 401, .. }) = &listed {
        // The agent refuses this token: it was revoked or removed there. Drop the dead token so
        // the window goes back to sign-in, and keep the pin, the account name and the device key.
        let dir = dir.to_path_buf();
        store
            .run(move |st| st.delete(&account("token", &dir)))
            .await
            .map_err(AgentError::Local)?;
    }
    listed
}

/// Creates a new identity for this computer on the user's request: the next sign-in enrolls a
/// new device row. Refused while signed in, because the saved login belongs to the old key's
/// device and would be left behind on the agent.
pub fn reset_device_key(dir: &Path, store: &dyn SecretStore) -> Result<(), String> {
    if !load_saved(dir, store)?.token.is_empty() {
        return Err("Sign out first; the saved login belongs to the current device key.".into());
    }
    Identity::reset(dir, store)
}

/// Removes the token from `state.json` first (always possible), then from the keystore, so a
/// locked keystore can never leave a plaintext copy behind.
pub fn sign_out(dir: &Path, store: &dyn SecretStore) -> Result<(), String> {
    let mut f = read_state(dir)?;
    if !f.token.is_empty() {
        f.token.clear();
        write_state(dir, &f)?;
    }
    store.delete(&account("token", dir))
}

/// What signing out did beyond clearing this computer.
#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SignOut {
    /// The agent no longer accepts the old token.
    pub revoked: bool,
    /// Set when the agent could not be told; says what is still valid and how to fix it.
    pub note: String,
}

/// Signs out: revokes this computer's device on the agent so the old token stops working, then
/// clears it locally ([`sign_out`]). The local part always runs, so an unreachable agent or a
/// changed certificate never leaves the token on this computer; the result says when the agent
/// could not be told.
pub async fn sign_out_and_revoke(dir: &Path, store: &Offloaded) -> Result<SignOut, String> {
    let state = read_state(dir)?;
    let token = {
        let dir = dir.to_path_buf();
        match store.run(move |s| s.get(&account("token", &dir))).await {
            Ok(Some(t)) => t,
            // A keystore that is locked still lets a pre-keystore file token be revoked.
            _ => state.token.clone(),
        }
    };
    let mut out = SignOut::default();
    if !token.is_empty() && !state.host.is_empty() && !state.device_id.is_empty() {
        let pinned = state.pins().get(&pin_key(&state.host)).cloned();
        let revoked = match pinned
            .ok_or_else(|| AgentError::Local("this agent is no longer trusted".into()))
            .and_then(|fp| AgentClient::pinned(&state.host, &fp))
        {
            Ok(c) => c.revoke_own_device(&token, &state.device_id).await,
            Err(e) => Err(e),
        };
        match revoked {
            Ok(()) => out.revoked = true,
            // The agent already refuses this token, which is what sign-out is for.
            Err(AgentError::Server { status: 401, .. }) => out.revoked = true,
            Err(e) => {
                out.note = format!(
                    "Signed out on this computer only. The agent could not be told ({e}), so this \
                     computer's login still works until it is revoked from the agent's device list \
                     or with `rfe-agent revoke` on the PC."
                );
            }
        }
    }
    let dir = dir.to_path_buf();
    store.run(move |s| sign_out(&dir, s)).await?;
    Ok(out)
}

/// One trusted agent, for the "trusted agents" list.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PinView {
    pub host: String,
    pub fingerprint: String,
    /// This computer is signed in to this agent now.
    pub active: bool,
}

pub fn list_pins(dir: &Path) -> Result<Vec<PinView>, String> {
    let f = read_state(dir)?;
    let active = (!f.host.is_empty()).then(|| pin_key(&f.host));
    Ok(f.pins()
        .iter()
        .map(|(host, fingerprint)| PinView {
            host: host.clone(),
            fingerprint: fingerprint.clone(),
            active: active.as_deref() == Some(host.as_str()),
        })
        .collect())
}

/// What forgetting a pin did.
#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ForgetPin {
    pub was_pinned: bool,
    /// The pin belonged to the agent this computer was signed in to, so the saved login was
    /// cleared here too. The device stays valid on the agent until it is revoked there.
    pub signed_out: bool,
}

/// Forgets the trust in one address. Connecting to it again shows the fingerprint to compare as
/// for a new agent. If this computer was signed in to it, the saved login is cleared too: the
/// session rested on that trust. That cannot revoke the device, because the agent is no longer
/// trusted enough to talk to.
pub fn forget_pin(dir: &Path, store: &dyn SecretStore, host: &str) -> Result<ForgetPin, String> {
    let key = pin_key(host);
    let mut f = read_state(dir)?;
    let mut out = ForgetPin {
        was_pinned: f.pins_mut().remove(&key).is_some(),
        signed_out: false,
    };
    if !f.host.is_empty() && pin_key(&f.host) == key {
        out.signed_out = true;
        f.host.clear();
        f.fingerprint.clear();
        f.username.clear();
        f.device_id.clear();
        f.token.clear();
        write_state(dir, &f)?;
        store.delete(&account("token", dir))?;
    } else if out.was_pinned {
        write_state(dir, &f)?;
    }
    Ok(out)
}
