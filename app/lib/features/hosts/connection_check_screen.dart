import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/health.dart';
import '../../core/models/host.dart';

/// Phase 0 connectivity check: enter a host agent address and ping `/health`.
/// This validates the app -> agent transport (TLS + pinning) end to end and is
/// the seed the full host-list / pairing flow grows from in Phase 1.
class ConnectionCheckScreen extends StatefulWidget {
  const ConnectionCheckScreen({super.key});

  @override
  State<ConnectionCheckScreen> createState() => _ConnectionCheckScreenState();
}

class _ConnectionCheckScreenState extends State<ConnectionCheckScreen> {
  final _controller = TextEditingController(text: '192.168.1.10:8765');
  Future<Health>? _result;
  String? _fingerprint;

  void _connect() {
    final host = Host(
      id: 'probe',
      label: 'probe',
      address: _controller.text.trim(),
    );
    final client = AgentClient(host);
    setState(() {
      _fingerprint = null;
      _result = client.health().whenComplete(() {
        setState(() => _fingerprint = client.lastSeenFingerprint);
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Remote File Explorer')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Agent address (host:port)',
                hintText: 'mypc.tailnet.ts.net:8765',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _connect,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Check connection'),
            ),
            const SizedBox(height: 24),
            Expanded(child: _buildResult()),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final result = _result;
    if (result == null) {
      return const Center(child: Text('Enter an agent address to begin.'));
    }
    return FutureBuilder<Health>(
      future: result,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Text('Failed: ${snap.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          );
        }
        final h = snap.data!;
        return ListView(
          children: [
            _row('Status', h.status),
            _row('Name', h.name),
            _row('Version', h.version),
            _row('OS', h.os),
            _row('Read-only', h.readOnly.toString()),
            if (_fingerprint != null) _row('Cert fingerprint', _fingerprint!),
          ],
        );
      },
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 130, child: Text(k, style: const TextStyle(fontWeight: FontWeight.bold))),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
