//! Secret storage for the device signing key and the login token.
//!
//! Secrets live in the OS keystore (Secret Service on Linux, Keychain on macOS, Credential
//! Manager on Windows). There is deliberately no file fallback: when the keystore is missing or
//! locked every operation fails with a message saying so, and nothing secret touches the disk.

use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::Duration;

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

/// What to do about a keystore failure, by cause. keyring maps "the service answered but refused"
/// (locked, no default keyring, prompt dismissed) to `NoStorageAccess` and "no service answered"
/// (no session bus, no provider) to `PlatformFailure`. Every message still says "OS keystore" and
/// that nothing is saved to files, so a caller can tell this failure from any other.
fn unavailable(e: keyring::Error) -> String {
    // A locked collection is reported by the service as a D-Bus error, which keyring files under
    // `PlatformFailure`; it is still a locked keystore, not a missing one.
    let refused = matches!(e, keyring::Error::NoStorageAccess(_))
        || e.to_string().to_ascii_lowercase().contains("locked");
    let (what, fix) = match &e {
        _ if refused => (
            "the OS keystore refused access",
            "Unlock it (log in again, or unlock the \"Login\" or default keyring or wallet), and \
             make sure a default keyring exists",
        ),
        keyring::Error::PlatformFailure(_) => (
            "no OS keystore answered",
            "Start a Secret Service provider and unlock it: gnome-keyring, KeePassXC (turn on \
             Secret Service Integration in its settings) or KDE Wallet. Over SSH or on a server \
             there is no desktop session bus; run the app inside a session that has one",
        ),
        _ => (
            "the OS keystore could not be used",
            "Check the keystore and try again",
        ),
    };
    format!("{what} ({e}). {fix}. Secrets are never saved to files")
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

/// A store whose calls can be made without blocking the async runtime.
///
/// Keystore calls are synchronous and can sit on an unlock prompt for as long as the user takes.
/// Run on a runtime worker (or Tauri's main thread for a sync command) that stalls every other
/// command, so async code goes through [`Offloaded::run`], which moves the call to a blocking
/// thread and gives up waiting after a timeout. The blocked thread itself cannot be cancelled: if
/// the user answers the prompt later, the call finishes and its result is dropped.
///
/// It also implements [`SecretStore`] by calling straight through, for code that is already
/// synchronous (tests, examples, `load_saved`).
#[derive(Clone)]
pub struct Offloaded {
    inner: Arc<dyn SecretStore>,
    timeout: Duration,
}

impl Offloaded {
    /// Long enough for a person to type a keyring password, short enough to end a hung session bus.
    pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(120);

    pub fn new(store: impl SecretStore + 'static) -> Self {
        Self {
            inner: Arc::new(store),
            timeout: Self::DEFAULT_TIMEOUT,
        }
    }

    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    /// Runs `f` against the store on a blocking thread.
    pub async fn run<T, F>(&self, f: F) -> Result<T, String>
    where
        T: Send + 'static,
        F: FnOnce(&dyn SecretStore) -> Result<T, String> + Send + 'static,
    {
        let store = Arc::clone(&self.inner);
        let task = tokio::task::spawn_blocking(move || f(&*store));
        match tokio::time::timeout(self.timeout, task).await {
            Ok(Ok(result)) => result,
            Ok(Err(e)) => Err(format!("the OS keystore call failed to run: {e}")),
            Err(_) => Err(format!(
                "the OS keystore did not answer within {:?}; an unlock prompt may be waiting \
                 behind another window. Unlock it and try again. Secrets are never saved to files",
                self.timeout
            )),
        }
    }
}

impl SecretStore for Offloaded {
    fn get(&self, account: &str) -> Result<Option<String>, String> {
        self.inner.get(account)
    }

    fn set(&self, account: &str, secret: &str) -> Result<(), String> {
        self.inner.set(account, secret)
    }

    fn delete(&self, account: &str) -> Result<(), String> {
        self.inner.delete(account)
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
