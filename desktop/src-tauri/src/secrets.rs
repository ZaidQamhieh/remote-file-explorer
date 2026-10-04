//! Secret storage for the device signing key and the login token.
//!
//! Secrets live in the OS keystore (Secret Service on Linux, Keychain on macOS, Credential
//! Manager on Windows). There is deliberately no file fallback: when the keystore is missing or
//! locked every operation fails with a message saying so, and nothing secret touches the disk.

use std::collections::HashMap;
use std::path::Path;
use std::sync::Mutex;

pub trait SecretStore: Send + Sync {
    /// `Ok(None)` means "no such secret"; any other failure is an error.
    fn get(&self, account: &str) -> Result<Option<String>, String>;
    fn set(&self, account: &str, secret: &str) -> Result<(), String>;
    /// Deleting a secret that does not exist is not an error.
    fn delete(&self, account: &str) -> Result<(), String>;
}

/// One keystore entry per secret kind and state directory, so separate state directories
/// (tests, a second profile) never share secrets.
pub fn account(kind: &str, dir: &Path) -> String {
    format!("{kind}:{}", dir.display())
}

#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
compile_error!("rfe-desktop has no OS keystore backend for this platform");

pub struct OsKeystore {
    service: String,
}

impl OsKeystore {
    pub fn new() -> Self {
        Self::with_service("rfe-desktop")
    }

    pub fn with_service(service: &str) -> Self {
        Self {
            service: service.to_string(),
        }
    }

    fn entry(&self, account: &str) -> Result<keyring::Entry, String> {
        keyring::Entry::new(&self.service, account).map_err(unavailable)
    }
}

impl Default for OsKeystore {
    fn default() -> Self {
        Self::new()
    }
}

fn unavailable(e: keyring::Error) -> String {
    format!(
        "the OS keystore is missing or locked ({e}); unlock it or start a Secret Service \
         provider (for example gnome-keyring or KWallet). Secrets are never saved to files"
    )
}

impl SecretStore for OsKeystore {
    fn get(&self, account: &str) -> Result<Option<String>, String> {
        match self.entry(account)?.get_password() {
            Ok(v) => Ok(Some(v)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(e) => Err(unavailable(e)),
        }
    }

    fn set(&self, account: &str, secret: &str) -> Result<(), String> {
        self.entry(account)?
            .set_password(secret)
            .map_err(unavailable)
    }

    fn delete(&self, account: &str) -> Result<(), String> {
        match self.entry(account)?.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(e) => Err(unavailable(e)),
        }
    }
}

/// In-memory store for tests and examples. Never used by the app.
#[derive(Default)]
pub struct MemoryStore {
    map: Mutex<HashMap<String, String>>,
}

impl SecretStore for MemoryStore {
    fn get(&self, account: &str) -> Result<Option<String>, String> {
        Ok(self.map.lock().unwrap().get(account).cloned())
    }

    fn set(&self, account: &str, secret: &str) -> Result<(), String> {
        self.map
            .lock()
            .unwrap()
            .insert(account.to_string(), secret.to_string());
        Ok(())
    }

    fn delete(&self, account: &str) -> Result<(), String> {
        self.map.lock().unwrap().remove(account);
        Ok(())
    }
}

/// A keystore that is missing or locked: every call fails like the real one does.
pub struct UnavailableStore;

impl SecretStore for UnavailableStore {
    fn get(&self, _: &str) -> Result<Option<String>, String> {
        Err(unavailable(keyring::Error::NoStorageAccess(
            "keystore is locked".into(),
        )))
    }

    fn set(&self, a: &str, _: &str) -> Result<(), String> {
        self.get(a).map(|_| ())
    }

    fn delete(&self, a: &str) -> Result<(), String> {
        self.get(a).map(|_| ())
    }
}
