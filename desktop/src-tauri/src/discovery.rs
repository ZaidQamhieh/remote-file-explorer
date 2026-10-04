//! Finding agents on the local network by mDNS/DNS-SD (`_rfe._tcp`).
//!
//! Discovery only produces addresses to try. It proves nothing: anyone on the network can
//! advertise this service name, so a found agent is exactly as untrusted as an address typed by
//! hand, and goes through the same certificate comparison before any credential is sent. This
//! module returns data and touches no secret and no connection to an agent.

use mdns_sd::{ServiceDaemon, ServiceEvent};
use serde::Serialize;
use std::collections::BTreeMap;
use std::net::IpAddr;
use std::time::{Duration, Instant};

pub const SERVICE: &str = "_rfe._tcp.local.";

/// Most agents listed; a network can be made to advertise any number.
const MAX_FOUND: usize = 50;

/// One advertised agent.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Found {
    /// The instance name the agent gave itself; display only.
    pub name: String,
    /// The address to try first, as `host:port`.
    pub hostport: String,
    /// Its other addresses, if it advertised several.
    pub other_addresses: Vec<String>,
    /// The version it advertised; display only.
    pub version: String,
}

/// Text from the network, made safe to show: no control characters, bounded length.
fn display(s: &str, max: usize) -> String {
    s.chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .take(max)
        .collect::<String>()
        .trim()
        .to_string()
}

fn is_link_local_v6(a: &std::net::Ipv6Addr) -> bool {
    (a.segments()[0] & 0xffc0) == 0xfe80
}

/// The `host:port` strings worth trying for these addresses, best first: IPv4 before IPv6, no
/// unspecified or multicast addresses, and no IPv6 link-local address (it cannot be used without
/// a zone, which the app does not accept). Every result passes the app's address check.
pub fn candidates(addrs: impl IntoIterator<Item = IpAddr>, port: u16) -> Vec<String> {
    let mut v4 = Vec::new();
    let mut v6 = Vec::new();
    for a in addrs {
        if a.is_unspecified() || a.is_multicast() {
            continue;
        }
        match a {
            IpAddr::V4(a) => v4.push(a),
            IpAddr::V6(a) if !is_link_local_v6(&a) => v6.push(a),
            IpAddr::V6(_) => {}
        }
    }
    v4.sort();
    v4.dedup();
    v6.sort();
    v6.dedup();
    let all = v4
        .into_iter()
        .map(|a| format!("{a}:{port}"))
        .chain(v6.into_iter().map(|a| format!("[{a}]:{port}")));
    all.filter(|hp| crate::agent_client::validate_hostport(hp).is_ok())
        .collect()
}

/// "pc._rfe._tcp.local." -> "pc"
fn instance_name(fullname: &str) -> &str {
    fullname
        .strip_suffix(SERVICE)
        .map(|n| n.trim_end_matches('.'))
        .unwrap_or(fullname)
}

/// Browses for `window` and returns what answered. An empty list is a normal result (no agent,
/// or a network that blocks multicast); an error means the browser itself could not start.
pub async fn discover(window: Duration) -> Result<Vec<Found>, String> {
    tokio::task::spawn_blocking(move || browse(window))
        .await
        .map_err(|e| format!("network discovery stopped: {e}"))?
}

fn browse(window: Duration) -> Result<Vec<Found>, String> {
    let daemon =
        ServiceDaemon::new().map_err(|e| format!("cannot start network discovery: {e}"))?;
    let events = daemon
        .browse(SERVICE)
        .map_err(|e| format!("cannot start network discovery: {e}"))?;
    let deadline = Instant::now() + window;
    let mut found: BTreeMap<String, Found> = BTreeMap::new();
    while let Some(left) = deadline.checked_duration_since(Instant::now()) {
        match events.recv_timeout(left) {
            Ok(ServiceEvent::ServiceResolved(r)) => {
                let mut list = candidates(r.addresses.iter().map(|a| a.to_ip_addr()), r.port);
                if list.is_empty() {
                    continue;
                }
                let first = list.remove(0);
                found.insert(
                    r.fullname.clone(),
                    Found {
                        name: display(instance_name(&r.fullname), 64),
                        hostport: first,
                        other_addresses: list,
                        version: display(
                            r.txt_properties
                                .get_property_val_str("version")
                                .unwrap_or(""),
                            32,
                        ),
                    },
                );
            }
            Ok(_) => {}
            Err(_) => break,
        }
    }
    let _ = daemon.shutdown();
    Ok(found.into_values().take(MAX_FOUND).collect())
}
