//! HTTPS client for the RFE agent with certificate pinning.
//!
//! The agent uses a self-signed certificate, so there is no CA to trust. The
//! identity of the agent is the SHA-256 of its leaf certificate (the same hex
//! string `rfe-agent status` prints). Two modes:
//!
//! - capture: accepts any certificate and records its fingerprint. Used only
//!   by `capture_fingerprint`, which sends one unauthenticated GET and no
//!   credentials, so the user can compare the fingerprint before trusting it.
//! - pinned: accepts only a certificate whose fingerprint matches. The only
//!   way to build an `AgentClient` (the type that can send a password or a
//!   token) is `AgentClient::pinned`, so credentials cannot go out on an
//!   unverified connection.

use crate::identity::Identity;
use hmac::{Hmac, Mac};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::{verify_tls12_signature, verify_tls13_signature, CryptoProvider};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{ClientConfig, DigitallySignedStruct, Error as TlsError, SignatureScheme};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::sync::{Arc, Mutex};
use std::time::Duration;

pub const CLIENT_VERSION: &str = concat!("desktop-", env!("CARGO_PKG_VERSION"));

#[derive(Debug)]
pub enum AgentError {
    /// Connection or TLS failure (including a fingerprint mismatch).
    Network(String),
    /// The agent answered with an error body `{code, message}`.
    Server {
        status: u16,
        code: String,
        message: String,
    },
    /// Bad local input or state.
    Local(String),
}

impl std::fmt::Display for AgentError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AgentError::Network(m) if m.contains("fingerprint mismatch") => write!(
                f,
                "This agent's certificate is not the one you trusted ({m}). Do not sign in. If you \
                 replaced or reinstalled the agent, forget it under Trusted agents and compare its \
                 fingerprint again."
            ),
            AgentError::Network(m) => write!(
                f,
                "cannot reach the agent securely: {m}. Check that the agent is running and the \
                 address is right."
            ),
            AgentError::Server { code, message, .. } => match known_message(code) {
                Some(text) => write!(f, "{text}"),
                None => write!(f, "{code}: {message}"),
            },
            AgentError::Local(m) => write!(f, "{m}"),
        }
    }
}

/// Every error code the agent's sign-in and pairing endpoints return, each with its own
/// wording and what to do next. A code not listed here is shown as the agent sent it.
pub const KNOWN_CODES: &[&str] = &[
    "INVALID_CREDENTIALS",
    "INVALID_CODE",
    "INVALID_NONCE",
    "INVALID_SIGNATURE",
    "DEVICE_KEY_REQUIRED",
    "DEVICE_KEY_MISMATCH",
    "RATE_LIMITED",
    "PAIR_BUSY",
    "UNAUTHORIZED",
    "FORBIDDEN",
    "NOT_FOUND",
    "BAD_REQUEST",
    "INTERNAL",
];

/// The message for an agent error code, or `None` for a code this app does not know.
pub fn known_message(code: &str) -> Option<&'static str> {
    Some(match code {
        "INVALID_CREDENTIALS" => "Wrong username or password.",
        "INVALID_CODE" => {
            "That pairing code is wrong, expired or already used. Generate a new one on the PC."
        }
        "INVALID_NONCE" => {
            "The agent no longer accepts this sign-in attempt (it expired or was already used). \
             Try again."
        }
        "INVALID_SIGNATURE" => {
            "The agent could not verify this computer's device key. Try again; if it keeps \
             failing, report it."
        }
        "DEVICE_KEY_REQUIRED" => {
            "The agent requires a device key proof that this app did not send. This is a bug in \
             the app."
        }
        "DEVICE_KEY_MISMATCH" => {
            "The agent already knows a different key for this computer. Remove this computer from \
             the agent's device list (rfe-agent remove <id> on the PC), then sign in again."
        }
        "RATE_LIMITED" => {
            "Too many attempts. The agent allows only a few sign-in and pairing attempts per \
             minute. Wait a minute, then try again."
        }
        "PAIR_BUSY" => {
            "The agent already has pairing requests waiting for approval on the PC. Answer them or \
             wait for them to expire, then try again."
        }
        "UNAUTHORIZED" => "The agent no longer accepts this login. Sign in again.",
        "FORBIDDEN" => {
            "This login is not allowed to do that. Sign in with the account, not a pairing code, \
             to manage devices."
        }
        "NOT_FOUND" => "The agent has no such item. It may have expired.",
        "BAD_REQUEST" => "The agent refused the request as malformed. This is a bug in the app.",
        "INTERNAL" => "The agent had an internal error. Check its log on the PC.",
        _ => return None,
    })
}

impl std::error::Error for AgentError {}

#[derive(Debug)]
enum Mode {
    Pin(String),
    Capture(Arc<Mutex<Option<String>>>),
}

#[derive(Debug)]
struct PinVerifier {
    mode: Mode,
    provider: Arc<CryptoProvider>,
}

fn fingerprint_of(der: &[u8]) -> String {
    hex::encode(Sha256::digest(der))
}

impl ServerCertVerifier for PinVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, TlsError> {
        let seen = fingerprint_of(end_entity.as_ref());
        match &self.mode {
            Mode::Pin(expected) => {
                if &seen == expected {
                    Ok(ServerCertVerified::assertion())
                } else {
                    Err(TlsError::General(format!(
                        "certificate fingerprint mismatch (pinned {expected}, agent presented {seen})"
                    )))
                }
            }
            Mode::Capture(slot) => {
                *slot.lock().unwrap() = Some(seen);
                Ok(ServerCertVerified::assertion())
            }
        }
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, TlsError> {
        verify_tls12_signature(
            message,
            cert,
            dss,
            &self.provider.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, TlsError> {
        verify_tls13_signature(
            message,
            cert,
            dss,
            &self.provider.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.provider
            .signature_verification_algorithms
            .supported_schemes()
    }
}

fn build_http(mode: Mode) -> Result<reqwest::Client, AgentError> {
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let config = ClientConfig::builder_with_provider(provider.clone())
        .with_safe_default_protocol_versions()
        .map_err(|e| AgentError::Local(format!("tls config: {e}")))?
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(PinVerifier { mode, provider }))
        .with_no_client_auth();
    reqwest::Client::builder()
        .use_preconfigured_tls(config)
        // Agent traffic goes straight to the agent; never via an environment proxy.
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(10))
        .build()
        .map_err(|e| AgentError::Local(format!("http client: {e}")))
}

/// Lowercase hex with separators and whitespace removed, so `AB:CD` and `abcd` compare equal.
pub fn normalize_fingerprint(s: &str) -> String {
    s.chars()
        .filter(|c| c.is_ascii_hexdigit())
        .collect::<String>()
        .to_ascii_lowercase()
}

/// The code both sides show so the user can tell the agent they reached is the one that holds the
/// certificate this app saw: `HMAC-SHA256(key = certificate SHA-256, msg = "rfe-pair-sas\n" +
/// clientNonce + requestId)`, first 8 bytes as a big-endian number mod 10^8, as "1234 5678". A
/// machine relaying the connection presents a different certificate and so gets a different code.
pub fn match_code(
    fingerprint_hex: &str,
    client_nonce_hex: &str,
    request_id: &str,
) -> Result<String, AgentError> {
    let fp = hex::decode(normalize_fingerprint(fingerprint_hex))
        .ok()
        .filter(|b| b.len() == 32)
        .ok_or_else(|| AgentError::Local("bad fingerprint".into()))?;
    let nonce = hex::decode(client_nonce_hex)
        .ok()
        .filter(|b| b.len() == 16)
        .ok_or_else(|| AgentError::Local("bad client nonce".into()))?;
    let mut mac = Hmac::<Sha256>::new_from_slice(&fp).expect("HMAC takes any key length");
    mac.update(b"rfe-pair-sas\n");
    mac.update(&nonce);
    mac.update(request_id.as_bytes());
    let digest = mac.finalize().into_bytes();
    let n = u64::from_be_bytes(digest[..8].try_into().expect("8 bytes")) % 100_000_000;
    Ok(format!("{:04} {:04}", n / 10_000, n % 10_000))
}

/// 16 random bytes, hex: the secret that authorises polling for one pairing request.
pub fn new_client_nonce() -> Result<String, AgentError> {
    let mut b = [0u8; 16];
    getrandom::getrandom(&mut b).map_err(|e| AgentError::Local(format!("random: {e}")))?;
    Ok(hex::encode(b))
}

/// `host:port` only: no scheme, path, userinfo or query, so a typo cannot
/// redirect credentials to another origin.
pub fn validate_hostport(hostport: &str) -> Result<(), AgentError> {
    let bad = || {
        AgentError::Local(
            "agent address must be host:port (put an IPv6 address in brackets, like [::1]:8765)"
                .into(),
        )
    };
    let ok_chars = hostport
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | ':' | '[' | ']'));
    let (host, port) = hostport.rsplit_once(':').ok_or_else(bad)?;
    let port_ok = port.parse::<u16>().map(|p| p != 0).unwrap_or(false);
    // A host with ':' is an IPv6 literal and must be bracketed; otherwise no brackets at all.
    let host_ok = if host.contains(':') {
        host.len() > 2
            && host.starts_with('[')
            && host.ends_with(']')
            && !host[1..host.len() - 1].contains(['[', ']'])
    } else {
        !host.is_empty() && !host.contains(['[', ']'])
    };
    if !ok_chars || !port_ok || !host_ok {
        return Err(bad());
    }
    Ok(())
}

fn net(e: reqwest::Error) -> AgentError {
    let mut msg = e.to_string();
    let mut src = std::error::Error::source(&e);
    while let Some(s) = src {
        msg = format!("{msg}: {s}");
        src = s.source();
    }
    AgentError::Network(msg)
}

/// Connects without trusting anything and returns the agent's certificate
/// fingerprint. Sends one unauthenticated GET and no credentials.
pub async fn capture_fingerprint(hostport: &str) -> Result<String, AgentError> {
    validate_hostport(hostport)?;
    let seen = Arc::new(Mutex::new(None));
    let http = build_http(Mode::Capture(seen.clone()))?;
    http.get(format!("https://{hostport}/v1/health"))
        .send()
        .await
        .map_err(net)?;
    let fp = seen.lock().unwrap().clone();
    fp.ok_or_else(|| AgentError::Local("the agent presented no certificate".into()))
}

#[derive(Deserialize)]
struct ApiError {
    code: String,
    message: String,
}

#[derive(Deserialize)]
struct Challenge {
    nonce: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LoginBody<'a> {
    username: &'a str,
    password: &'a str,
    device_label: &'a str,
    device_id: &'a str,
    device_public_key: String,
    nonce: String,
    signature: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PairBody<'a> {
    pairing_code: &'a str,
    device_label: &'a str,
    device_id: &'a str,
    device_public_key: String,
    nonce: String,
    signature: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PairRequestBody<'a> {
    device_label: &'a str,
    device_id: &'a str,
    device_public_key: String,
    nonce: String,
    signature: String,
    client_nonce: &'a str,
}

/// A pairing request the agent is holding for the owner to answer.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PairRequestStarted {
    pub request_id: String,
    pub expires_in_seconds: u64,
}

/// Where a pairing request stands. `Approved` carries the token and is returned once only.
#[derive(Debug)]
pub enum PairPoll {
    Pending,
    Rejected,
    Approved(LoginOk),
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", default)]
#[derive(Default)]
struct PollBody {
    status: String,
    device_token: String,
    device_id: String,
    agent_name: String,
    cert_fingerprint: String,
}

#[derive(Default, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct LoginOk {
    pub device_token: String,
    pub device_id: String,
    pub agent_name: String,
    pub cert_fingerprint: String,
}

// Not derived: a `{:?}` in a log line or a test failure must not print the device token.
impl std::fmt::Debug for LoginOk {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("LoginOk")
            .field("device_token", &"<redacted>")
            .field("device_id", &self.device_id)
            .field("agent_name", &self.agent_name)
            .field("cert_fingerprint", &self.cert_fingerprint)
            .finish()
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Device {
    pub id: String,
    pub label: String,
    pub created: i64,
    pub last_seen: i64,
    pub revoked: bool,
    pub current: bool,
    pub last_address: String,
    pub last_version: String,
    pub via_login: bool,
}

pub struct AgentClient {
    http: reqwest::Client,
    base: String,
    fingerprint: String,
}

async fn parse<T: serde::de::DeserializeOwned>(resp: reqwest::Response) -> Result<T, AgentError> {
    let status = resp.status();
    if status.is_success() {
        return resp
            .json::<T>()
            .await
            .map_err(|e| AgentError::Local(format!("unexpected response: {e}")));
    }
    Err(error_of(resp).await)
}

/// The error for a non-success response: the agent's `{code, message}` body when it has one.
async fn error_of(resp: reqwest::Response) -> AgentError {
    let code = resp.status().as_u16();
    let body = resp.bytes().await.unwrap_or_default();
    match serde_json::from_slice::<ApiError>(&body) {
        Ok(e) => AgentError::Server {
            status: code,
            code: e.code,
            message: e.message,
        },
        Err(_) => AgentError::Server {
            status: code,
            code: format!("HTTP_{code}"),
            message: "the agent returned an unexpected error".into(),
        },
    }
}

impl AgentClient {
    /// The only constructor. `fingerprint` must be the 64-hex SHA-256 the user trusted.
    pub fn pinned(hostport: &str, fingerprint: &str) -> Result<Self, AgentError> {
        validate_hostport(hostport)?;
        let fp = normalize_fingerprint(fingerprint);
        if fp.len() != 64 {
            return Err(AgentError::Local(
                "fingerprint must be 64 hex characters".into(),
            ));
        }
        Ok(Self {
            http: build_http(Mode::Pin(fp.clone()))?,
            base: format!("https://{hostport}/v1"),
            fingerprint: fp,
        })
    }

    async fn challenge(&self) -> Result<String, AgentError> {
        let c: Challenge = parse(
            self.http
                .post(format!("{}/auth/challenge", self.base))
                .send()
                .await
                .map_err(net)?,
        )
        .await?;
        Ok(c.nonce)
    }

    /// The TLS pin already guarantees the certificate; the agent's own statement of its
    /// fingerprint is a second check that fails loudly if the two ever differ.
    fn check_fingerprint(&self, ok: &LoginOk) -> Result<(), AgentError> {
        if !ok.cert_fingerprint.is_empty()
            && normalize_fingerprint(&ok.cert_fingerprint) != self.fingerprint
        {
            return Err(AgentError::Local(
                "the agent reports a different fingerprint than the pinned one".into(),
            ));
        }
        Ok(())
    }

    pub async fn login(
        &self,
        id: &Identity,
        username: &str,
        password: &str,
        label: &str,
    ) -> Result<LoginOk, AgentError> {
        let nonce = self.challenge().await?;
        let body = LoginBody {
            username,
            password,
            device_label: label,
            device_id: id.device_id(),
            device_public_key: id.public_key_b64(),
            signature: id.sign_b64(&nonce),
            nonce,
        };
        let ok: LoginOk = parse(
            self.http
                .post(format!("{}/login", self.base))
                .json(&body)
                .send()
                .await
                .map_err(net)?,
        )
        .await?;
        self.check_fingerprint(&ok)?;
        Ok(ok)
    }

    /// Enrolls with a one-time pairing code (`POST /pair`). The agent checks the device proof
    /// before it spends the code, so a failed attempt does not burn a valid one. The token this
    /// returns belongs to an ordinary device, not an admin one.
    pub async fn pair(
        &self,
        id: &Identity,
        code: &str,
        label: &str,
    ) -> Result<LoginOk, AgentError> {
        let nonce = self.challenge().await?;
        let body = PairBody {
            pairing_code: code,
            device_label: label,
            device_id: id.device_id(),
            device_public_key: id.public_key_b64(),
            signature: id.sign_b64(&nonce),
            nonce,
        };
        let ok: LoginOk = parse(
            self.http
                .post(format!("{}/pair", self.base))
                .json(&body)
                .send()
                .await
                .map_err(net)?,
        )
        .await?;
        self.check_fingerprint(&ok)?;
        Ok(ok)
    }

    /// Asks the owner to approve this computer at the PC (`POST /pair/request`). The device proof
    /// goes with it; `client_nonce` is the secret needed to poll for the answer.
    pub async fn pair_request(
        &self,
        id: &Identity,
        label: &str,
        client_nonce: &str,
    ) -> Result<PairRequestStarted, AgentError> {
        let nonce = self.challenge().await?;
        let body = PairRequestBody {
            device_label: label,
            device_id: id.device_id(),
            device_public_key: id.public_key_b64(),
            signature: id.sign_b64(&nonce),
            nonce,
            client_nonce,
        };
        parse(
            self.http
                .post(format!("{}/pair/request", self.base))
                .json(&body)
                .send()
                .await
                .map_err(net)?,
        )
        .await
    }

    /// Asks how a pairing request stands (`GET /pair/request/{id}`). The approval, with the
    /// token, is handed out once: a second poll gets `NOT_FOUND`.
    pub async fn poll_pair_request(
        &self,
        request_id: &str,
        client_nonce: &str,
    ) -> Result<PairPoll, AgentError> {
        if request_id.is_empty() || !request_id.chars().all(|c| c.is_ascii_alphanumeric()) {
            return Err(AgentError::Local(format!(
                "unexpected request id {request_id:?}"
            )));
        }
        let body: PollBody = parse(
            self.http
                .get(format!("{}/pair/request/{request_id}", self.base))
                .query(&[("nonce", client_nonce)])
                .send()
                .await
                .map_err(net)?,
        )
        .await?;
        match body.status.as_str() {
            "pending" => Ok(PairPoll::Pending),
            "rejected" => Ok(PairPoll::Rejected),
            "approved" => {
                let ok = LoginOk {
                    device_token: body.device_token,
                    device_id: body.device_id,
                    agent_name: body.agent_name,
                    cert_fingerprint: body.cert_fingerprint,
                };
                self.check_fingerprint(&ok)?;
                Ok(PairPoll::Approved(ok))
            }
            other => Err(AgentError::Local(format!(
                "the agent answered with an unknown pairing status {other:?}"
            ))),
        }
    }

    /// Revokes this computer's own device on the agent (`DELETE /devices/{id}`), after which the
    /// agent rejects `token`. Any device may do this to itself, admin or not.
    pub async fn revoke_own_device(&self, token: &str, device_id: &str) -> Result<(), AgentError> {
        if device_id.is_empty()
            || !device_id
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
        {
            return Err(AgentError::Local(format!(
                "unexpected device id {device_id:?}"
            )));
        }
        let resp = self
            .http
            .delete(format!("{}/devices/{device_id}", self.base))
            .bearer_auth(token)
            .header("X-RFE-Client-Version", CLIENT_VERSION)
            .send()
            .await
            .map_err(net)?;
        if resp.status().is_success() {
            Ok(())
        } else {
            Err(error_of(resp).await)
        }
    }

    pub async fn devices(&self, token: &str) -> Result<Vec<Device>, AgentError> {
        parse(
            self.http
                .get(format!("{}/devices", self.base))
                .bearer_auth(token)
                .header("X-RFE-Client-Version", CLIENT_VERSION)
                .send()
                .await
                .map_err(net)?,
        )
        .await
    }
}

// ---- feature:health-metrics ----
impl AgentClient {
    /// `GET` one of the agent's fixed, read-only routes as a signed-in device and parses the JSON
    /// answer. `path` is a `'static` literal chosen by the app (never text from the window), and
    /// `timeout` bounds the whole request, so an agent that accepts the connection and then says
    /// nothing, or a PC that fell off the network, ends in an error instead of a wait.
    pub async fn get_fixed_json<T: serde::de::DeserializeOwned>(
        &self,
        token: &str,
        path: &'static str,
        timeout: Duration,
    ) -> Result<T, AgentError> {
        debug_assert!(path.starts_with('/') && !path.contains(['?', '#', ' ']));
        let resp = self
            .http
            .get(format!("{}{path}", self.base))
            .bearer_auth(token)
            .header("X-RFE-Client-Version", CLIENT_VERSION)
            .timeout(timeout)
            .send()
            .await
            .map_err(|e| {
                if e.is_timeout() {
                    let secs = timeout.as_secs().max(1);
                    AgentError::Local(format!(
                        "The agent did not answer within {secs} second{}. It may be asleep, busy \
                         or on another network; check that it is running and the address is right.",
                        if secs == 1 { "" } else { "s" }
                    ))
                } else {
                    net(e)
                }
            })?;
        parse(resp).await
    }
}
