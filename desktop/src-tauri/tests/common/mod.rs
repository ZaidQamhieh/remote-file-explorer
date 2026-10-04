//! Shared by the agent-backed integration tests: starts a throwaway `rfe-agent` on a random
//! loopback port with its own data and roots directories. Set RFE_AGENT_BIN to a built agent.
#![allow(dead_code)]

use rfe_desktop_lib::agent_client::normalize_fingerprint;
use std::net::{TcpListener, TcpStream};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};
use tempfile::TempDir;

pub fn agent_bin() -> PathBuf {
    PathBuf::from(
        std::env::var("RFE_AGENT_BIN").expect("set RFE_AGENT_BIN to a built rfe-agent binary"),
    )
}

pub fn free_port() -> u16 {
    TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port()
}

pub fn cli(args: &[&str]) -> String {
    let out = Command::new(agent_bin())
        .args(args)
        .output()
        .expect("run rfe-agent");
    let text = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(out.status.success(), "rfe-agent {args:?} failed: {text}");
    text
}

pub struct Agent {
    child: Child,
    data: TempDir,
    _roots: TempDir,
    pub host: String,
}

impl Agent {
    pub fn start(port: u16) -> Self {
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
        Agent {
            child,
            data,
            _roots: roots,
            host,
        }
    }

    pub fn dir(&self) -> &str {
        self.data.path().to_str().unwrap()
    }

    pub fn add_user(&self, user: &str, password: &str) {
        cli(&["adduser", "-password", password, "-data", self.dir(), user]);
    }

    /// Ground truth: the fingerprint the agent itself reports.
    pub fn status_fingerprint(&self) -> String {
        let out = cli(&["status", "-data", self.dir()]);
        let line = out
            .lines()
            .find(|l| l.starts_with("fingerprint:"))
            .expect("fingerprint line");
        normalize_fingerprint(line.trim_start_matches("fingerprint:"))
    }

    pub fn devices_cli(&self) -> String {
        cli(&["devices", "-data", self.dir()])
    }

    pub fn audit_cli(&self) -> String {
        cli(&["audit", "-data", self.dir()])
    }

    pub fn stop(mut self) -> TempDir {
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
