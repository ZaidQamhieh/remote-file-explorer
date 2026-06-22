import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nsd/nsd.dart';

/// An RFE agent discovered on the local network via mDNS.
class DiscoveredAgent {
  const DiscoveredAgent({
    required this.name,
    required this.address,
    required this.port,
    this.version,
  });

  final String name;
  final String address;
  final int port;
  final String? version;

  /// Address in `host:port` format, matching [Host.address].
  String get hostAddress => '$address:$port';
}

/// Wraps the `nsd` package to discover `_rfe._tcp` services on the LAN.
///
/// Call [start] to begin scanning and listen to [agents] for updates.
/// Call [stop] when done to release platform resources.
class MdnsDiscovery {
  Discovery? _discovery;
  final _controller = StreamController<List<DiscoveredAgent>>.broadcast();
  final _agents = <String, DiscoveredAgent>{};

  /// Stream of currently visible agents, emitted on every change.
  Stream<List<DiscoveredAgent>> get agents => _controller.stream;

  /// Snapshot of agents visible right now.
  List<DiscoveredAgent> get current => _agents.values.toList();

  Future<void> start() async {
    _discovery = await startDiscovery('_rfe._tcp');
    _discovery!.addServiceListener((service, status) {
      final addr = service.host;
      final port = service.port;
      if (addr == null || port == null) return;

      final key = '$addr:$port';
      final txt = service.txt;
      final name = _decodeTxt(txt, 'name') ?? service.name ?? addr;
      final version = _decodeTxt(txt, 'version');

      if (status == ServiceStatus.found) {
        _agents[key] = DiscoveredAgent(
          name: name,
          address: addr,
          port: port,
          version: version,
        );
      } else {
        _agents.remove(key);
      }
      _controller.add(_agents.values.toList());
    });
  }

  Future<void> stop() async {
    if (_discovery != null) {
      await stopDiscovery(_discovery!);
    }
    _agents.clear();
    _controller.close();
  }
}

/// Decodes a single TXT record value from bytes to a UTF-8 string.
String? _decodeTxt(Map<String, dynamic>? txt, String key) {
  if (txt == null) return null;
  final value = txt[key];
  if (value == null) return null;
  if (value is List<int>) return utf8.decode(value);
  return value.toString();
}

/// Provides a live stream of discovered RFE agents on the local network.
///
/// Auto-disposes when no widget is watching, which stops the mDNS scan and
/// releases platform resources.
final mdnsDiscoveryProvider = StreamProvider.autoDispose<List<DiscoveredAgent>>(
  (ref) {
    final discovery = MdnsDiscovery();
    discovery.start();
    ref.onDispose(() => discovery.stop());
    return discovery.agents;
  },
);
