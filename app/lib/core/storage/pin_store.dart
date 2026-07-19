import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPinsKey = 'offline_pins_v1';

/// A folder pinned for offline caching on a specific host.
class Pin {
  const Pin({required this.hostId, required this.remotePath});

  final String hostId;
  final String remotePath;

  factory Pin.fromJson(Map<String, dynamic> j) =>
      Pin(hostId: j['hostId'] as String, remotePath: j['remotePath'] as String);

  Map<String, dynamic> toJson() => {'hostId': hostId, 'remotePath': remotePath};
}

/// Reactive store of offline-pinned folders, persisted in SharedPreferences.
class PinNotifier extends AsyncNotifier<List<Pin>> {
  SharedPreferences? _prefs;

  @override
  Future<List<Pin>> build() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getStringList(_kPinsKey) ?? [];
    final pins = <Pin>[];
    for (final s in raw) {
      try {
        pins.add(Pin.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // Skip one corrupt/legacy entry rather than bricking offline pins
        // entirely (PR-54).
      }
    }
    return pins;
  }

  List<Pin> get _current => List<Pin>.from(state.valueOrNull ?? []);

  Future<void> _persist(List<Pin> pins) async {
    await _prefs?.setStringList(
      _kPinsKey,
      pins.map((p) => jsonEncode(p.toJson())).toList(),
    );
    state = AsyncData(pins);
  }

  bool isPinned(String hostId, String remotePath) => (state.valueOrNull ?? [])
      .any((p) => p.hostId == hostId && p.remotePath == remotePath);

  /// All pinned paths for a single host.
  List<String> pinsForHost(String hostId) =>
      (state.valueOrNull ?? [])
          .where((p) => p.hostId == hostId)
          .map((p) => p.remotePath)
          .toList();

  Future<void> pin(String hostId, String remotePath) async {
    final pins = _current;
    if (pins.any((p) => p.hostId == hostId && p.remotePath == remotePath)) {
      return;
    }
    pins.add(Pin(hostId: hostId, remotePath: remotePath));
    await _persist(pins);
  }

  Future<void> unpin(String hostId, String remotePath) async {
    final pins =
        _current..removeWhere(
          (p) => p.hostId == hostId && p.remotePath == remotePath,
        );
    await _persist(pins);
  }
}

final pinStoreProvider = AsyncNotifierProvider<PinNotifier, List<Pin>>(
  PinNotifier.new,
);
