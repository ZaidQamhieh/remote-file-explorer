//! The in-memory log is what a user may attach to a bug report, so after real sign-ins it must
//! hold neither the password, nor the login token, nor the pairing code. Its own test binary: the
//! log is process-wide and this test is the only one in the process.

mod common;

use common::{free_port, Agent};
use rfe_desktop_lib::agent_client::capture_fingerprint;
use rfe_desktop_lib::applog::{self, Level};
use rfe_desktop_lib::flows;
use rfe_desktop_lib::secrets::{MemoryStore, Offloaded};
use tempfile::TempDir;

#[tokio::test]
async fn the_log_holds_no_secret_after_a_real_sign_in_and_pairing() {
    applog::clear();
    applog::set_level(Level::Debug);
    const PW: &str = "pw-that-must-not-be-logged";
    let agent = Agent::start(free_port());
    agent.add_user("owner", PW);
    let fp = capture_fingerprint(&agent.host).await.unwrap();
    let dir = TempDir::new().unwrap();
    let store = Offloaded::new(MemoryStore::default());

    // A wrong password first: the failure is logged, the password still is not.
    let bad = flows::login(
        dir.path(),
        &agent.host,
        &fp,
        "owner",
        "wrong-pw-xyz",
        "D",
        &store,
    )
    .await
    .unwrap_err();
    assert!(
        bad.to_string().contains("Wrong username or password"),
        "{bad}"
    );
    let saved = flows::login(dir.path(), &agent.host, &fp, "owner", PW, "Desktop", &store)
        .await
        .unwrap();
    let devices = flows::list_devices(dir.path(), &store).await.unwrap();
    assert_eq!(devices.len(), 1);

    let code = agent.pair_code();
    let other = TempDir::new().unwrap();
    let paired = flows::pair(other.path(), &agent.host, &fp, &code, "Second", &store)
        .await
        .unwrap();

    let text = applog::lines().join("\n");
    assert!(text.contains("sign-in to"), "the flow is logged: {text}");
    assert!(text.contains("failed"), "the failure is logged: {text}");
    for secret in [
        PW,
        "wrong-pw-xyz",
        saved.token.as_str(),
        paired.token.as_str(),
        code.as_str(),
    ] {
        assert!(
            !secret.is_empty() && !text.contains(secret),
            "{secret} leaked:\n{text}"
        );
    }
    applog::clear();
    applog::set_level(Level::Info);
}
