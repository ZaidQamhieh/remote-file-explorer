/// A paired host agent the app can connect to, over LAN or Tailscale.
class Host {
  const Host({
    required this.id,
    required this.label,
    required this.address,
    this.certFingerprint,
    this.tailscaleName,
  });

  final String id;
  final String label;

  /// Base address without scheme, e.g. `192.168.1.20:8765` or
  /// `mypc.tailnet.ts.net:8765`.
  final String address;

  /// SHA-256 of the agent's TLS certificate, pinned at pairing time (TOFU).
  final String? certFingerprint;

  /// Tailscale MagicDNS name, used when off the local network.
  final String? tailscaleName;

  Uri get baseUri => Uri.parse('https://$address/v1');
}
