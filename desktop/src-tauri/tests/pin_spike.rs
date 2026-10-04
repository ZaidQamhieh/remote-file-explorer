//! Spike and acceptance tests for the first slice, run against throwaway
//! agents (explicit -addr/-data/-roots, random loopback port, temp dirs).
//! Set RFE_AGENT_BIN to a built `rfe-agent` binary.

use rfe_desktop_lib::agent_client::{
    capture_fingerprint, normalize_fingerprint, validate_hostport, AgentClient, AgentError,
};
use rfe_desktop_lib::flows;
use rfe_desktop_lib::identity::Identity;
use std::net::{TcpListener, TcpStream};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};
use tempfile::TempDir;

fn agent_bin() -> PathBuf {
    PathBuf::from(std::env::var("RFE_AGENT_BIN").expect("set RFE_AGENT_BIN to a built rfe-agent binary"))
}

fn free_port() -> u16 {
    TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port()
}

fn cli(args: &[&str]) -> String {
    let out = Command::new(agent_bin()).args(args).output().expect("run rfe-agent");
    let text = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(out.status.success(), "rfe-agent {args:?} failed: {text}");
    text
}

struct Agent {
    child: Child,
    data: TempDir,
    _roots: TempDir,
    host: String,
}

impl Agent {
    fn start(port: u16) -> Self {
        let data = TempDir::new().unwrap();
        let roots = TempDir::new().unwrap();
        let host = format!("127.0.0.1:{port}");
        let child = Command::new(agent_bin())
            .args(["-addr", &host, "-name", "rfe-desktop-test"])
            .args(["-data", data.path().to_str().unwrap()])
            .args(["-roots", roots.path().to_str().unwrap()])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .expect("start rfe-agent");
        let deadline = Instant::now() + Duration::from_secs(20);
        while TcpStream::connect(&host).is_err() {
            assert!(Instant::now() < deadline, "agent did not start on {host}");
            std::thread::sleep(Duration::from_millis(100));
        }
        Agent { child, data, _roots: roots, host }
    }

    fn dir(&self) -> &str {
        self.data.path().to_str().unwrap()
    }

    fn add_user(&self, user: &str, password: &str) {
        cli(&["adduser", "-password", password, "-data", self.dir(), user]);
    }

    /// Ground truth: the fingerprint the agent itself reports.
    fn status_fingerprint(&self) -> String {
        let out = cli(&["status", "-data", self.dir()]);
        let line = out.lines().find(|l| l.starts_with("fingerprint:")).expect("fingerprint line");
        normalize_fingerprint(line.trim_start_matches("fingerprint:"))
    }

    fn devices_cli(&self) -> String {
        cli(&["devices", "-data", self.dir()])
    }

    fn audit_cli(&self) -> String {
        cli(&["audit", "-data", self.dir()])
    }

    fn stop(mut self) -> TempDir {
        let _ = self.child.kill();
        let _ = self.child.wait();
        // keep the data dir alive for the caller by moving it out
        std::mem::replace(&mut self.data, TempDir::new().unwrap())
    }
}

impl Drop for Agent {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

#[tokio::test]
async fn captured_fingerprint_matches_the_agents_own_report() {
    let a = Agent::start(free_port());
    let seen = capture_fingerprint(&a.host).await.unwrap();
    assert_eq!(seen.len(), 64);
    assert_eq!(seen, a.status_fingerprint());
}

#[tokio::test]
async fn pinned_login_lists_the_full_device_list() {
    let a = Agent::start(free_port());
    a.add_user("owner", "correct horse battery");
    let fp = capture_fingerprint(&a.host).await.unwrap();
    let state = TempDir::new().unwrap();

    let saved = flows::login(state.path(), &a.host, &fp, "owner", "correct horse battery", "Desktop A")
        .await
        .expect("login through the pin");
    assert!(!saved.token.is_empty());

    // A second login device (different identity) so "full list" is not just "me".
    let other = TempDir::new().unwrap();
    flows::login(other.path(), &a.host, &fp, "owner", "correct horse battery", "Desktop B")
        .await
        .unwrap();

    // The agent assigns the device row id; the client-sent id is its separate client id.
    assert!(Identity::load_or_create(state.path()).unwrap().device_id().starts_with("desktop-"));
    let list = flows::list_devices(state.path()).await.unwrap();
    assert_eq!(list.len(), 2, "admin session must see both devices: {list:?}");
    let current: Vec<_> = list.iter().filter(|d| d.current).collect();
    assert_eq!(current.len(), 1);
    assert_eq!(current[0].id, saved.device_id);
    assert!(!saved.device_id.is_empty());
    assert!(list.iter().all(|d| d.via_login));
    assert!(list.iter().any(|d| d.label == "Desktop B"));
    assert!(a.devices_cli().contains("Desktop B"), "CLI ground truth agrees");
}

#[tokio::test]
async fn wrong_pin_is_refused_and_sends_no_credentials() {
    let a = Agent::start(free_port());
    a.add_user("owner", "pw-for-wrong-pin-test");
    let state = TempDir::new().unwrap();
    let wrong = "0".repeat(64);

    let err = flows::login(state.path(), &a.host, &wrong, "owner", "pw-for-wrong-pin-test", "X")
        .await
        .expect_err("a wrong pin must fail");
    assert!(matches!(err, AgentError::Network(_)), "expected a TLS failure, got {err:?}");
    assert!(err.to_string().contains("fingerprint mismatch"), "{err}");

    // Nothing reached the server: no device row and no login/failed-login audit entry.
    assert!(a.devices_cli().contains("No paired devices"), "{}", a.devices_cli());
    let audit = a.audit_cli();
    assert!(!audit.contains("login"), "agent saw a login attempt: {audit}");

    // Negative control: the same agent and credentials succeed with the right pin.
    let fp = capture_fingerprint(&a.host).await.unwrap();
    flows::login(state.path(), &a.host, &fp, "owner", "pw-for-wrong-pin-test", "X")
        .await
        .expect("right pin must work");
    assert!(a.audit_cli().contains("login"));
}

#[tokio::test]
async fn a_changed_certificate_after_pairing_is_refused() {
    let port = free_port();
    let first = Agent::start(port);
    first.add_user("owner", "pw-for-cert-change");
    let fp1 = capture_fingerprint(&first.host).await.unwrap();
    let state = TempDir::new().unwrap();
    flows::login(state.path(), &first.host, &fp1, "owner", "pw-for-cert-change", "Desktop")
        .await
        .unwrap();
    assert_eq!(flows::list_devices(state.path()).await.unwrap().len(), 1);
    let same = flows::probe(state.path(), &first.host).await.unwrap();
    assert!(!same.changed && same.previous == fp1, "unchanged cert must not warn: {same:?}");
    let _old_data = first.stop();

    // Same address, new data dir = new certificate (an impostor or a reinstalled agent).
    let second = Agent::start(port);
    second.add_user("owner", "pw-for-cert-change");
    let fp2 = capture_fingerprint(&second.host).await.unwrap();
    assert_ne!(fp1, fp2, "control: the second agent really has a different certificate");

    let probe = flows::probe(state.path(), &second.host).await.unwrap();
    assert!(probe.changed, "a different cert at the same address must be flagged");
    assert_eq!(probe.previous, fp1);
    assert_eq!(probe.fingerprint, fp2);

    let err = flows::list_devices(state.path()).await.expect_err("saved pin must refuse the new cert");
    assert!(matches!(err, AgentError::Network(_)), "{err:?}");
    let err = flows::login(state.path(), &second.host, &fp1, "owner", "pw-for-cert-change", "Desktop")
        .await
        .expect_err("login must refuse the new cert");
    assert!(matches!(err, AgentError::Network(_)), "{err:?}");
    assert!(second.devices_cli().contains("No paired devices"));
    assert!(!second.audit_cli().contains("login"));
}

#[tokio::test]
async fn wrong_password_surfaces_the_agents_error_code() {
    let a = Agent::start(free_port());
    a.add_user("owner", "the-right-one");
    let fp = capture_fingerprint(&a.host).await.unwrap();
    let state = TempDir::new().unwrap();
    let err = flows::login(state.path(), &a.host, &fp, "owner", "not-it", "X").await.unwrap_err();
    match err {
        AgentError::Server { status, code, .. } => {
            assert_eq!(status, 401);
            assert_eq!(code, "INVALID_CREDENTIALS");
        }
        other => panic!("expected a server error, got {other:?}"),
    }
}

#[test]
fn host_and_fingerprint_inputs_are_validated() {
    for bad in [
        "evil.com/path:1", "user@host:8765", "https://h:1", "host", "host:99999", ":8765",
        "::1:8765", "a:b:c:80", "127.0.0.1:0", "[::1:8765", "[]:8765", "h[1]:80",
    ] {
        assert!(validate_hostport(bad).is_err(), "{bad} should be rejected");
    }
    assert!(validate_hostport("127.0.0.1:8765").is_ok());
    assert!(validate_hostport("[::1]:8765").is_ok());
    assert!(validate_hostport("my-pc.local:8765").is_ok());
    assert_eq!(normalize_fingerprint("AB:cd ef"), "abcdef");
    assert!(AgentClient::pinned("127.0.0.1:8765", "abc").is_err());
}

#[test]
fn damaged_state_and_identity_files_are_errors_not_resets() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join("state.json"), b"{not json").unwrap();
    assert!(flows::load_saved(dir.path()).is_err());
    assert_eq!(std::fs::read(dir.path().join("state.json")).unwrap(), b"{not json");
    // Control: a missing file is simply "not configured".
    assert!(flows::load_saved(TempDir::new().unwrap().path()).unwrap().host.is_empty());

    // An unreadable identity (a directory where the file should be) must not mint a new key.
    let idir = TempDir::new().unwrap();
    std::fs::create_dir(idir.path().join("identity.json")).unwrap();
    assert!(Identity::load_or_create(idir.path()).is_err());
    assert!(idir.path().join("identity.json").is_dir(), "the existing entry was left alone");
    // Control: a fresh dir creates one, and loading it again returns the same device id.
    let fresh = TempDir::new().unwrap();
    let first = Identity::load_or_create(fresh.path()).unwrap();
    let again = Identity::load_or_create(fresh.path()).unwrap();
    assert_eq!(first.device_id(), again.device_id());
    assert_eq!(first.public_key_b64(), again.public_key_b64());
}

#[test]
fn private_writes_replace_atomically_stay_0600_and_ignore_loose_leftovers() {
    use rfe_desktop_lib::flows::{save, load_saved, Saved};
    let dir = TempDir::new().unwrap();
    // A loose-permission file at the old fixed temp name must not be reused.
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let stale = dir.path().join("state.tmp");
        std::fs::write(&stale, b"old").unwrap();
        std::fs::set_permissions(&stale, std::fs::Permissions::from_mode(0o644)).unwrap();
    }
    let s = Saved { host: "h:1".into(), token: "secret".into(), ..Default::default() };
    save(dir.path(), &s).unwrap();
    save(dir.path(), &s).unwrap();
    assert_eq!(load_saved(dir.path()).unwrap().token, "secret");
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = std::fs::metadata(dir.path().join("state.json")).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600, "state.json must be owner-only");
        let leftovers: Vec<_> = std::fs::read_dir(dir.path()).unwrap()
            .filter_map(|e| e.ok()).map(|e| e.file_name().to_string_lossy().to_string())
            .filter(|n| n.contains(".tmp.")).collect();
        assert!(leftovers.is_empty(), "temp files left behind: {leftovers:?}");
    }
}
