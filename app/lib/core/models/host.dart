/// The kind of address used to reach a paired host.
enum HostRoute { lan, tailscale, directHttps, custom }

/// A paired host address, annotated with the route that owns it.
class HostRouteAddress {
  const HostRouteAddress({required this.route, required this.address});

  final HostRoute route;
  final String address;
}

/// A paired host agent the app can reach over LAN, Tailscale, or direct HTTPS.
class Host {
  const Host({
    required this.id,
    required this.label,
    required this.address,
    this.certFingerprint,
    this.tailscaleName,
    this.tailscaleAddress,
    this.internetAddress,
    this.macAddress,
  });

  final String id;
  final String label;

  /// Primary base address without scheme, e.g. `192.168.1.20:8765`. Usually
  /// the LAN address captured at pairing time.
  final String address;

  /// SHA-256 of the agent TLS certificate, mirrored in host metadata for
  /// compatibility. Paired-host trust decisions use the secure-store copy.
  final String? certFingerprint;

  /// Tailscale MagicDNS name; the current Flutter app does not browse mDNS.
  final String? tailscaleName;

  /// Secondary address reachable over Tailscale, e.g. `100.x.y.z:8765`.
  /// Captured at pairing time or learned later from a successful `/health`
  /// call — lets the app reach this host both at home (LAN) and away
  /// (Tailscale) without the user managing two separate entries.
  final String? tailscaleAddress;

  /// Optional public HTTPS endpoint configured by the device owner, e.g.
  /// `files.example.com` or `files.example.com:8765`. The app always adds the
  /// HTTPS scheme itself and still requires the host's pinned certificate.
  final String? internetAddress;

  /// MAC address of the host's LAN interface, cached from `/health` for
  /// Wake-on-LAN when the host is asleep. Absent until the first successful
  /// health ping from an agent that reports it.
  final String? macAddress;

  /// Candidate authorities in connection-attempt order: LAN, Tailscale, then
  /// the optional direct HTTPS endpoint. Duplicates keep their highest
  /// priority route metadata.
  List<HostRouteAddress> get routeAddresses {
    final seen = <String>{};
    final candidates = <HostRouteAddress?>[
      HostRouteAddress(route: HostRoute.lan, address: address),
      if (tailscaleAddress != null)
        HostRouteAddress(
          route: HostRoute.tailscale,
          address: tailscaleAddress!,
        ),
      if (internetAddress != null && isValidInternetAddress(internetAddress!))
        HostRouteAddress(
          route: HostRoute.directHttps,
          address: internetAddress!,
        ),
    ];
    return [
      for (final candidate in candidates)
        if (candidate != null &&
            candidate.address.isNotEmpty &&
            seen.add(candidate.address))
          candidate,
    ];
  }

  List<String> get addresses =>
      routeAddresses.map((candidate) => candidate.address).toList();

  /// Resolves an address to its configured route without relying on localized
  /// display text. Duplicate addresses map to their highest-priority route.
  HostRoute routeForAddress(String address) {
    for (final candidate in routeAddresses) {
      if (candidate.address == address) return candidate.route;
    }
    return HostRoute.custom;
  }

  Uri get baseUri => Uri.parse('https://$address/v1');

  factory Host.fromJson(Map<String, dynamic> json) => Host(
    id: json['id'] as String,
    label: json['label'] as String,
    address: json['address'] as String,
    certFingerprint: json['certFingerprint'] as String?,
    tailscaleName: json['tailscaleName'] as String?,
    tailscaleAddress: json['tailscaleAddress'] as String?,
    internetAddress: json['internetAddress'] as String?,
    macAddress: json['macAddress'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'address': address,
    if (certFingerprint != null) 'certFingerprint': certFingerprint,
    if (tailscaleName != null) 'tailscaleName': tailscaleName,
    if (tailscaleAddress != null) 'tailscaleAddress': tailscaleAddress,
    if (internetAddress != null) 'internetAddress': internetAddress,
    if (macAddress != null) 'macAddress': macAddress,
  };

  Host copyWith({
    String? id,
    String? label,
    String? address,
    String? certFingerprint,
    String? tailscaleName,
    String? tailscaleAddress,
    String? internetAddress,
    bool clearInternetAddress = false,
    String? macAddress,
  }) => Host(
    id: id ?? this.id,
    label: label ?? this.label,
    address: address ?? this.address,
    certFingerprint: certFingerprint ?? this.certFingerprint,
    tailscaleName: tailscaleName ?? this.tailscaleName,
    tailscaleAddress: tailscaleAddress ?? this.tailscaleAddress,
    internetAddress:
        clearInternetAddress ? null : internetAddress ?? this.internetAddress,
    macAddress: macAddress ?? this.macAddress,
  );

  /// Validates the authority-only syntax accepted for a direct HTTPS route.
  /// The caller must add the scheme; paths, credentials, and URL components
  /// are rejected so this value cannot redirect API requests elsewhere.
  static bool isValidInternetAddress(String value) {
    if (value.isEmpty || value != value.trim()) return false;
    if (RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(value) ||
        RegExp(r'[/\\?#@]').hasMatch(value)) {
      return false;
    }

    final ipv6 = RegExp(
      r'^\[([0-9A-Fa-f:.]+)\](?::([0-9]{1,5}))?$',
    ).firstMatch(value);
    if (ipv6 != null) {
      final address = ipv6.group(1)!;
      if (!_validIpv6Address(address)) {
        return false;
      }
      return _validPort(ipv6.group(2));
    }

    final authority = RegExp(
      r'^([^:\[\]]+)(?::([0-9]{1,5}))?$',
    ).firstMatch(value);
    if (authority == null) return false;
    final hostname = authority.group(1)!;
    if (hostname.length > 253) return false;
    if (RegExp(r'^[0-9]+(?:\.[0-9]+){3}$').hasMatch(hostname) &&
        !_validIpv4Address(hostname)) {
      return false;
    }
    final labels = hostname.split('.');
    if (labels.any(
      (label) =>
          label.isEmpty ||
          label.length > 63 ||
          !RegExp(
            r'^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$',
          ).hasMatch(label),
    )) {
      return false;
    }
    return _validPort(authority.group(2));
  }

  static bool _validPort(String? port) {
    if (port == null) return true;
    final value = int.tryParse(port);
    return value != null && value >= 1 && value <= 65535;
  }

  static bool _validIpv4Address(String address) {
    final octets = address.split('.');
    return octets.length == 4 &&
        octets.every((octet) {
          if (octet.isEmpty || octet.length > 3) return false;
          final value = int.tryParse(octet);
          return value != null && value >= 0 && value <= 255;
        });
  }

  static bool _validIpv6Address(String address) {
    if (!address.contains(':')) return false;
    final compressionAt = address.indexOf('::');
    final compressed = compressionAt >= 0;
    if (compressed && address.indexOf('::', compressionAt + 2) >= 0) {
      return false;
    }

    final segments =
        compressed
            ? [
              if (compressionAt > 0)
                ...address.substring(0, compressionAt).split(':'),
              if (compressionAt + 2 < address.length)
                ...address.substring(compressionAt + 2).split(':'),
            ]
            : address.split(':');
    if (segments.any((segment) => segment.isEmpty)) return false;

    var units = 0;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (segment.contains('.')) {
        if (i != segments.length - 1 || !_validIpv4Address(segment)) {
          return false;
        }
        units += 2;
      } else {
        if (segment.length > 4 ||
            !RegExp(r'^[0-9A-Fa-f]{1,4}$').hasMatch(segment)) {
          return false;
        }
        units++;
      }
    }

    return compressed ? units < 8 : units == 8;
  }
}
