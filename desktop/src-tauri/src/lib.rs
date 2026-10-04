//! RFE desktop app, first slice: pin the agent's certificate, log in, list devices.
//! The device key and login token are kept in the OS keystore.

pub mod agent_client;
pub mod applog;
pub mod flows;
mod fsutil;
pub mod identity;
pub mod secrets;

use agent_client::Device;
use flows::Saved;
use secrets::{Offloaded, OsKeystore};
use serde::Serialize;
use std::sync::Mutex;
use tauri::Manager;

fn keystore() -> Offloaded {
    Offloaded::new(OsKeystore::new())
}

fn data_dir(app: &tauri::AppHandle) -> Result<std::path::PathBuf, String> {
    app.path().app_data_dir().map_err(|e| e.to_string())
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SavedView {
    host: String,
    fingerprint: String,
    signed_in: bool,
    username: String,
    /// The agent's id for this computer; shown in Settings, not a secret.
    device_id: String,
}

impl From<Saved> for SavedView {
    fn from(s: Saved) -> Self {
        Self {
            signed_in: !s.token.is_empty(),
            host: s.host,
            fingerprint: s.fingerprint,
            username: s.username,
            device_id: s.device_id,
        }
    }
}

// Every command that touches the keystore is async and goes through `Offloaded`, so an open
// unlock prompt never blocks the main thread or a runtime worker.
#[tauri::command]
async fn saved_agent(app: tauri::AppHandle) -> Result<SavedView, String> {
    let dir = data_dir(&app)?;
    let saved = keystore().run(move |s| flows::load_saved(&dir, s)).await?;
    Ok(saved.into())
}

#[tauri::command]
fn list_pins(app: tauri::AppHandle) -> Result<Vec<flows::PinView>, String> {
    flows::list_pins(&data_dir(&app)?)
}

#[tauri::command]
async fn forget_pin(app: tauri::AppHandle, host: String) -> Result<flows::ForgetPin, String> {
    let dir = data_dir(&app)?;
    keystore()
        .run(move |s| flows::forget_pin(&dir, s, &host))
        .await
}

#[tauri::command]
async fn probe_agent(app: tauri::AppHandle, host: String) -> Result<flows::Probe, String> {
    flows::probe(&data_dir(&app)?, &host)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn login(
    app: tauri::AppHandle,
    host: String,
    fingerprint: String,
    username: String,
    password: String,
) -> Result<SavedView, String> {
    let dir = data_dir(&app)?;
    flows::login(
        &dir,
        &host,
        &fingerprint,
        &username,
        &password,
        "RFE Desktop",
        &keystore(),
    )
    .await
    .map(Into::into)
    .map_err(|e| e.to_string())
}

#[tauri::command]
async fn pair_with_code(
    app: tauri::AppHandle,
    host: String,
    fingerprint: String,
    code: String,
) -> Result<SavedView, String> {
    flows::pair(
        &data_dir(&app)?,
        &host,
        &fingerprint,
        &code,
        "RFE Desktop",
        &keystore(),
    )
    .await
    .map(Into::into)
    .map_err(|e| e.to_string())
}

/// The pairing request this window is waiting on. Only one at a time: asking again replaces it.
#[derive(Default)]
struct PendingPair(Mutex<Option<flows::PairWait>>);

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PairWaitView {
    match_code: String,
    expires_in_seconds: u64,
}

#[tauri::command]
async fn request_pairing(
    app: tauri::AppHandle,
    pending: tauri::State<'_, PendingPair>,
    host: String,
    fingerprint: String,
) -> Result<PairWaitView, String> {
    let wait = flows::request_pairing(
        &data_dir(&app)?,
        &host,
        &fingerprint,
        "RFE Desktop",
        &keystore(),
    )
    .await
    .map_err(|e| e.to_string())?;
    let view = PairWaitView {
        match_code: wait.match_code.clone(),
        expires_in_seconds: wait.expires_in_seconds,
    };
    *pending.0.lock().unwrap() = Some(wait);
    Ok(view)
}

#[derive(Serialize)]
struct PollView {
    /// "pending", "rejected", "expired" or "approved".
    status: &'static str,
    saved: Option<SavedView>,
}

#[tauri::command]
async fn poll_pairing(
    app: tauri::AppHandle,
    pending: tauri::State<'_, PendingPair>,
) -> Result<PollView, String> {
    let wait = pending
        .0
        .lock()
        .unwrap()
        .clone()
        .ok_or_else(|| "no pairing request is waiting".to_string())?;
    let progress = flows::poll_pairing(&data_dir(&app)?, &wait, &keystore()).await;
    let view = |status, saved| PollView { status, saved };
    match progress {
        Ok(flows::PairProgress::Pending) => Ok(view("pending", None)),
        Ok(flows::PairProgress::Rejected) => {
            pending.0.lock().unwrap().take();
            Ok(view("rejected", None))
        }
        Ok(flows::PairProgress::Expired) => {
            pending.0.lock().unwrap().take();
            Ok(view("expired", None))
        }
        Ok(flows::PairProgress::Approved(saved)) => {
            pending.0.lock().unwrap().take();
            Ok(view("approved", Some(saved.into())))
        }
        Err(e) => {
            // An error after the agent handed out the approval cannot be retried: the request
            // is spent. Keep waiting only for errors that left it untouched.
            if matches!(e, agent_client::AgentError::Local(_)) {
                pending.0.lock().unwrap().take();
            }
            Err(e.to_string())
        }
    }
}

#[tauri::command]
async fn reset_device_key(app: tauri::AppHandle) -> Result<(), String> {
    let dir = data_dir(&app)?;
    keystore()
        .run(move |s| flows::reset_device_key(&dir, s))
        .await
}

#[tauri::command]
fn cancel_pairing(pending: tauri::State<'_, PendingPair>) {
    pending.0.lock().unwrap().take();
}

#[tauri::command]
async fn list_devices(app: tauri::AppHandle) -> Result<Vec<Device>, String> {
    flows::list_devices(&data_dir(&app)?, &keystore())
        .await
        .map_err(|e| e.to_string())
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SettingsView {
    log_level: &'static str,
    app_version: &'static str,
    client_version: &'static str,
    min_agent_for_approval: &'static str,
    data_dir: String,
    platform: &'static str,
}

#[tauri::command]
fn app_settings(app: tauri::AppHandle) -> Result<SettingsView, String> {
    let dir = data_dir(&app)?;
    Ok(SettingsView {
        log_level: flows::log_level(&dir)?.as_str(),
        app_version: env!("CARGO_PKG_VERSION"),
        client_version: agent_client::CLIENT_VERSION,
        min_agent_for_approval: flows::MIN_AGENT_FOR_APPROVAL,
        data_dir: dir.display().to_string(),
        platform: std::env::consts::OS,
    })
}

#[tauri::command]
fn set_log_level(app: tauri::AppHandle, level: String) -> Result<&'static str, String> {
    flows::set_log_level(&data_dir(&app)?, &level).map(|l| l.as_str())
}

#[tauri::command]
async fn check_keystore(app: tauri::AppHandle) -> Result<(), String> {
    let dir = data_dir(&app)?;
    keystore()
        .run(move |s| flows::check_keystore(&dir, s))
        .await
}

#[tauri::command]
async fn sign_out(app: tauri::AppHandle) -> Result<flows::SignOut, String> {
    flows::sign_out_and_revoke(&data_dir(&app)?, &keystore()).await
}

pub fn run() {
    tauri::Builder::default()
        .manage(PendingPair::default())
        .setup(|app| {
            if let Ok(dir) = app.path().app_data_dir() {
                flows::apply_log_level(&dir);
            }
            applog::info(&format!("started {}", agent_client::CLIENT_VERSION));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            saved_agent,
            list_pins,
            forget_pin,
            probe_agent,
            login,
            pair_with_code,
            request_pairing,
            poll_pairing,
            cancel_pairing,
            reset_device_key,
            list_devices,
            sign_out,
            app_settings,
            set_log_level,
            check_keystore
        ])
        .run(tauri::generate_context!())
        .expect("error while running the RFE desktop app");
}
