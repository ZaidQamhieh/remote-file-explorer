//! App-level flows shared by the Tauri commands and the integration tests.

use crate::agent_client::{capture_fingerprint, normalize_fingerprint, AgentClient, AgentError, Device};
use crate::identity::Identity;
use crate::fsutil::write_private;
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Saved {
    pub host: String,
    pub fingerprint: String,
    pub token: String,
    pub username: String,
    /// The agent-assigned id of this computer's device row.
    pub device_id: String,
}

/// Missing file means "never configured". Any other read or parse failure is an
/// error, so a damaged state file cannot silently drop the pin and token.
pub fn load_saved(dir: &Path) -> Result<Saved, String> {
    let path = dir.join("state.json");
    match std::fs::read(&path) {
        Ok(bytes) => serde_json::from_slice(&bytes).map_err(|e| {
            format!("{} is damaged ({e}); delete it to start over", path.display())
        }),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Saved::default()),
        Err(e) => Err(format!("read {}: {e}", path.display())),
    }
}

pub fn save(dir: &Path, s: &Saved) -> Result<(), String> {
    let json = serde_json::to_vec_pretty(s).map_err(|e| e.to_string())?;
    write_private(&dir.join("state.json"), &json)
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
    let saved = load_saved(dir).map_err(AgentError::Local)?;
    let fingerprint = capture_fingerprint(host).await?;
    let previous = if saved.host == host { saved.fingerprint } else { String::new() };
    let changed = !previous.is_empty() && previous != fingerprint;
    Ok(Probe { fingerprint, previous, changed })
}

/// Pins `fingerprint` (the one the user confirmed), logs in, and stores the pin and token.
pub async fn login(
    dir: &Path,
    host: &str,
    fingerprint: &str,
    username: &str,
    password: &str,
    label: &str,
) -> Result<Saved, AgentError> {
    let identity = Identity::load_or_create(dir).map_err(AgentError::Local)?;
    let client = AgentClient::pinned(host, fingerprint)?;
    let ok = client.login(&identity, username, password, label).await?;
    let saved = Saved {
        host: host.to_string(),
        fingerprint: normalize_fingerprint(fingerprint),
        token: ok.device_token,
        username: username.to_string(),
        device_id: ok.device_id,
    };
    save(dir, &saved).map_err(AgentError::Local)?;
    Ok(saved)
}

pub async fn list_devices(dir: &Path) -> Result<Vec<Device>, AgentError> {
    let s = load_saved(dir).map_err(AgentError::Local)?;
    if s.token.is_empty() || s.host.is_empty() {
        return Err(AgentError::Local("not signed in".into()));
    }
    AgentClient::pinned(&s.host, &s.fingerprint)?.devices(&s.token).await
}

pub fn sign_out(dir: &Path) -> Result<(), String> {
    let mut s = load_saved(dir)?;
    s.token.clear();
    save(dir, &s)
}
