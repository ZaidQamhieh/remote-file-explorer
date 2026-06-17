import 'dart:io';
import 'dart:typed_data';

/// Sends a Wake-on-LAN magic packet to [macAddress].
///
/// The magic packet is 6 bytes of 0xFF followed by the target MAC address
/// repeated 16 times, sent as a UDP broadcast on port 9. [macAddress] must
/// be colon-separated (e.g. "aa:bb:cc:dd:ee:ff").
///
/// Returns `true` if the packet was sent successfully, `false` on any error
/// (invalid MAC, network failure, etc.). A successful send does NOT guarantee
/// the host will wake — the NIC must have WOL enabled in BIOS/OS settings.
Future<bool> sendWakeOnLan(String macAddress) async {
  final macBytes = _parseMac(macAddress);
  if (macBytes == null) return false;

  // Build magic packet: 6x 0xFF + 16x MAC.
  final packet = Uint8List(6 + 16 * 6);
  for (var i = 0; i < 6; i++) {
    packet[i] = 0xFF;
  }
  for (var i = 0; i < 16; i++) {
    packet.setRange(6 + i * 6, 6 + (i + 1) * 6, macBytes);
  }

  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    socket.send(packet, InternetAddress('255.255.255.255'), 9);
    return true;
  } catch (_) {
    return false;
  } finally {
    socket?.close();
  }
}

/// Parses a colon-separated MAC address into 6 bytes, or `null` if invalid.
Uint8List? _parseMac(String mac) {
  final parts = mac.split(':');
  if (parts.length != 6) return null;
  try {
    final bytes = Uint8List(6);
    for (var i = 0; i < 6; i++) {
      bytes[i] = int.parse(parts[i], radix: 16);
    }
    return bytes;
  } catch (_) {
    return null;
  }
}
