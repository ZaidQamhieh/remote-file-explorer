//! App-level flows shared by the Tauri commands and the integration tests.

use crate::agent_client::{
    capture_fingerprint, normalize_fingerprint, AgentClient, AgentError, Device,
};
use crate::fsutil::write_private;
use crate::identity::Identity;
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::secrets::{account, SecretStore};

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
        Ok(bytes) => serde_json::from_slice(&bytes).map_err(|e| {
            format!(
                "{} is damaged ({e}); delete it to start over",
                path.display()
            )
        }),
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
    write_state(
        dir,
        &StateFile {
            host: s.host.clone(),
            fingerprint: s.fingerprint.clone(),
            username: s.username.clone(),
            device_id: s.device_id.clone(),
            token: String::new(),
        },
    )
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
    let previous = if saved.host == host {
        saved.fingerprint
    } else {
        String::new()
    };
    let changed = !previous.is_empty() && previous != fingerprint;
    Ok(Probe {
        fingerprint,
        previous,
        changed,
    })
}

/// Pins `fingerprint` (the one the user confirmed), logs in, and stores the pin and token.
pub async fn login(
    dir: &Path,
    host: &str,
    fingerprint: &str,
    username: &str,
    password: &str,
    label: &str,
    store: &dyn SecretStore,
) -> Result<Saved, AgentError> {
    // Before any network traffic: a missing or locked keystore must stop the login here.
    let identity = Identity::load_or_create(dir, store).map_err(AgentError::Local)?;
    let client = AgentClient::pinned(host, fingerprint)?;
    let ok = client.login(&identity, username, password, label).await?;
    let saved = Saved {
        host: host.to_string(),
        fingerprint: normalize_fingerprint(fingerprint),
        token: ok.device_token,
        username: username.to_string(),
        device_id: ok.device_id,
    };
    save(dir, store, &saved).map_err(AgentError::Local)?;
    Ok(saved)
}

pub async fn list_devices(dir: &Path, store: &dyn SecretStore) -> Result<Vec<Device>, AgentError> {
    let s = load_saved(dir, store).map_err(AgentError::Local)?;
    if s.token.is_empty() || s.host.is_empty() {
        return Err(AgentError::Local("not signed in".into()));
    }
    AgentClient::pinned(&s.host, &s.fingerprint)?
        .devices(&s.token)
        .await
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
