//! RFE desktop app, first slice: pin the agent's certificate, log in, list devices.
//! The device key and login token are kept in the OS keystore.

pub mod agent_client;
pub mod flows;
mod fsutil;
pub mod identity;
pub mod secrets;

use agent_client::Device;
use flows::Saved;
use secrets::OsKeystore;
use serde::Serialize;
use tauri::Manager;

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
}

impl From<Saved> for SavedView {
    fn from(s: Saved) -> Self {
        Self {
            signed_in: !s.token.is_empty(),
            host: s.host,
            fingerprint: s.fingerprint,
            username: s.username,
        }
    }
}

#[tauri::command]
fn saved_agent(app: tauri::AppHandle) -> Result<SavedView, String> {
    Ok(flows::load_saved(&data_dir(&app)?, &OsKeystore::new())?.into())
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
        &OsKeystore::new(),
    )
    .await
    .map(Into::into)
    .map_err(|e| e.to_string())
}

#[tauri::command]
async fn list_devices(app: tauri::AppHandle) -> Result<Vec<Device>, String> {
    flows::list_devices(&data_dir(&app)?, &OsKeystore::new())
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
fn sign_out(app: tauri::AppHandle) -> Result<(), String> {
    flows::sign_out(&data_dir(&app)?, &OsKeystore::new())
}

pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            saved_agent,
            probe_agent,
            login,
            list_devices,
            sign_out
        ])
        .run(tauri::generate_context!())
        .expect("error while running the RFE desktop app");
}
