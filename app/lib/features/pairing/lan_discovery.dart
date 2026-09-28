import 'dart:io';

import 'package:flutter/services.dart';

/// An untrusted LAN candidate returned by Android's DNS-SD browser.
///
/// mDNS only helps locate an address. It does not authenticate the host; the
/// normal pairing flow still requires an independently verified certificate
/// fingerprint and a one-time pairing code.
class DiscoveredAgent {
  const DiscoveredAgent({
    required this.name,
    required this.address,
    required this.port,
  });

  final String name;
  final String address;
  final int port;

  String get authority => '$address:$port';

  static DiscoveredAgent? fromPlatform(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    final address = value['address'];
    final port = value['port'];
    if (name is! String || address is! String || port is! int) return null;

    final cleanName = name.trim();
    final cleanAddress = address.trim();
    if (cleanName.isEmpty ||
        cleanName.length > 128 ||
        !_isIpv4Address(cleanAddress) ||
        port < 1 ||
        port > 65535) {
      return null;
    }
    return DiscoveredAgent(name: cleanName, address: cleanAddress, port: port);
  }

  static bool _isIpv4Address(String value) {
    final parts = value.split('.');
    if (parts.length != 4) return false;
    return parts.every((part) {
      if (part.isEmpty || part.length > 3) return false;
      final octet = int.tryParse(part);
      return octet != null && octet >= 0 && octet <= 255;
    });
  }
}

/// Small Android-only bridge to the platform DNS-SD browser.
class LanDiscovery {
  LanDiscovery._();

  static const _channel = MethodChannel('rfe/discovery');

  static bool get isSupported => Platform.isAndroid;

  static Future<List<DiscoveredAgent>> scan() async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeListMethod<Object?>('scan');
    if (raw == null) return const [];

    final agents = <String, DiscoveredAgent>{};
    for (final item in raw) {
      final agent = DiscoveredAgent.fromPlatform(item);
      if (agent != null) agents[agent.authority] = agent;
    }
    return agents.values.toList(growable: false);
  }

  static Future<void> stop() async {
    if (isSupported) await _channel.invokeMethod<void>('stop');
  }
}
