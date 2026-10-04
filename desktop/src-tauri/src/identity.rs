//! Persistent Ed25519 device identity. The agent pins the public key to the
//! device row at enrollment and checks a signature over a fresh nonce.

use crate::fsutil::write_private;
use base64::{engine::general_purpose::STANDARD, Engine};
use ed25519_dalek::{Signer, SigningKey};
use serde::{Deserialize, Serialize};
use std::path::Path;

pub struct Identity {
    device_id: String,
    key: SigningKey,
}

#[derive(Serialize, Deserialize)]
struct IdentityFile {
    device_id: String,
    private_key: String,
}

fn random<const N: usize>() -> Result<[u8; N], String> {
    let mut buf = [0u8; N];
    getrandom::getrandom(&mut buf).map_err(|e| format!("random: {e}"))?;
    Ok(buf)
}

impl Identity {
    pub fn load_or_create(dir: &Path) -> Result<Self, String> {
        let path = dir.join("identity.json");
        match std::fs::read(&path) {
            Ok(bytes) => {
                return Self::from_file(&bytes).map_err(|e| {
                    format!(
                        "{} is damaged ({e}); delete it to create a new device identity",
                        path.display()
                    )
                })
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(format!("read {}: {e}", path.display())),
        }
        let key = SigningKey::from_bytes(&random::<32>()?);
        let device_id = format!("desktop-{}", hex::encode(random::<12>()?));
        let file = IdentityFile {
            device_id: device_id.clone(),
            private_key: STANDARD.encode(key.to_bytes()),
        };
        let json = serde_json::to_vec(&file).map_err(|e| e.to_string())?;
        write_private(&path, &json)?;
        Ok(Self { device_id, key })
    }

    fn from_file(bytes: &[u8]) -> Result<Self, String> {
        let f: IdentityFile =
            serde_json::from_slice(bytes).map_err(|e| format!("identity.json: {e}"))?;
        let raw = STANDARD
            .decode(&f.private_key)
            .map_err(|e| format!("identity key: {e}"))?;
        let arr: [u8; 32] = raw
            .try_into()
            .map_err(|_| "identity key must be 32 bytes".to_string())?;
        Ok(Self {
            device_id: f.device_id,
            key: SigningKey::from_bytes(&arr),
        })
    }

    pub fn device_id(&self) -> &str {
        &self.device_id
    }

    pub fn public_key_b64(&self) -> String {
        STANDARD.encode(self.key.verifying_key().to_bytes())
    }

    /// Signs the nonce string's UTF-8 bytes, which is what the agent verifies.
    pub fn sign_b64(&self, message: &str) -> String {
        STANDARD.encode(self.key.sign(message.as_bytes()).to_bytes())
    }
}
