//! RFE desktop app, first slice: pin the agent's certificate, log in, list devices.
//! The device key and login token are kept in the OS keystore.

pub mod agent_client;
pub mod applog;
pub mod apps; // feature:app-catalog
pub mod audit; // feature:audit-logs
pub mod device_actions;
pub mod discovery;
pub mod files; // feature:file-browser
pub mod flows;
mod fsutil;
pub mod health;
pub mod hosts;
pub mod identity;
pub mod pair_inbox; // feature:pair-inbox
pub mod pairing_codes; // feature:pairing-codes
pub mod secrets;
// ---- feature:transfers ----
pub mod transfers;

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

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct FoundView {
    #[serde(flatten)]
    found: discovery::Found,
    /// This app already trusts a certificate for that address.
    known: bool,
}

/// Looks for agents on the local network for a few seconds. The result is a list of addresses to
/// try, nothing more: no credential is sent and no agent is trusted by being listed.
#[tauri::command]
async fn discover_agents(app: tauri::AppHandle) -> Result<Vec<FoundView>, String> {
    let dir = data_dir(&app)?;
    let list = flows::discover(&dir, std::time::Duration::from_secs(3)).await?;
    Ok(list
        .into_iter()
        .map(|(found, known)| FoundView { found, known })
        .collect())
}

#[tauri::command]
fn diagnostics(app: tauri::AppHandle) -> Result<String, String> {
    Ok(flows::diagnostics(&data_dir(&app)?))
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

// ---- feature:health-metrics ----
/// One refresh of the health and metrics screen for the saved session. Takes no argument: the
/// address and certificate are the ones already trusted, and the three routes are fixed.
#[tauri::command]
async fn agent_health(app: tauri::AppHandle) -> Result<health::Snapshot, String> {
    health::agent_health(&data_dir(&app)?, &keystore())
        .await
        .map_err(|e| e.to_string())
}

// ---- feature:pairing-codes ----
/// Mints a one-time pairing code for a phone. Admin sessions only; any other session gets
/// `status: "forbidden"`. The code is never logged or saved.
#[tauri::command]
async fn generate_pairing_code(app: tauri::AppHandle) -> Result<pairing_codes::CodeView, String> {
    pairing_codes::generate(&data_dir(&app)?, &keystore())
        .await
        .map_err(|e| e.to_string())
}

// ---- feature:audit-logs ----
/// One page of the agent's audit trail (admin only). `before` is the cursor from the previous page.
#[tauri::command]
async fn audit_page(
    app: tauri::AppHandle,
    before: Option<i64>,
) -> Result<audit::AuditReply, String> {
    audit::fetch_audit(&data_dir(&app)?, &keystore(), before, audit::AUDIT_PAGE)
        .await
        .map_err(|e| e.to_string())
}

/// The tail of the agent's log (admin only).
#[tauri::command]
async fn agent_log(app: tauri::AppHandle) -> Result<audit::LogsReply, String> {
    audit::fetch_logs(&data_dir(&app)?, &keystore())
        .await
        .map_err(|e| e.to_string())
}

pub fn run() {
    tauri::Builder::default()
        // First, as the plugin requires: a second launch hands over to the running app, which
        // brings its window forward, and the second process exits.
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            applog::info("a second launch was handed over to this window");
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.unminimize();
                let _ = w.show();
                let _ = w.set_focus();
            }
        }))
        // Remembers the window's size and position between runs (kept in the app's config folder;
        // it holds nothing but geometry).
        .plugin(tauri_plugin_window_state::Builder::default().build())
        .manage(PendingPair::default())
        // ---- feature:transfers ----
        .manage(transfers::Transfers::default())
        .setup(|app| {
            if let Ok(dir) = app.path().app_data_dir() {
                flows::apply_log_level(&dir);
            }
            applog::info(&format!("started {}", agent_client::CLIENT_VERSION));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            // feature:file-browser
            files::files_roots,
            files::files_list,
            files::files_meta,
            files::files_create_folder,
            files::files_rename,
            files::files_trash,
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
            discover_agents,
            diagnostics,
            set_log_level,
            check_keystore,
            apps::list_host_apps,  // feature:app-catalog
            apps::launch_host_app, // feature:app-catalog
            agent_health,
            generate_pairing_code, // feature:pairing-codes
            audit_page,            // feature:audit-logs
            agent_log,
            // feature:device-actions
            device_actions::commands::device_access,
            device_actions::commands::set_device_access,
            device_actions::commands::revoke_device,
            device_actions::commands::remove_device,
            // feature:pair-inbox
            pair_inbox::list_pair_requests,
            pair_inbox::answer_pair_request,
            // feature:multi-hosts
            hosts::list_hosts,
            hosts::switch_host,
            hosts::rename_host,
            hosts::remove_host,
            // ---- feature:transfers ----
            transfers::transfer_download,
            transfers::transfer_upload,
            transfers::transfer_list,
            transfers::transfer_cancel,
            transfers::transfer_retry,
            transfers::transfer_clear_finished,
            transfers::transfer_folder
        ])
        .run(tauri::generate_context!())
        .expect("error while running the RFE desktop app");
}
