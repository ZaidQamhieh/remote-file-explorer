import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/health.dart';
import '../../core/models/host.dart';
import '../../core/theme/tokens.dart';

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
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Agent address (host:port)',
                hintText: 'mypc.tailnet.ts.net:8765',
              ),
            ),
            const SizedBox(height: Spacing.md),
            FilledButton.icon(
              onPressed: _connect,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Check connection'),
            ),
            const SizedBox(height: Spacing.lg),
            Expanded(child: _buildResult()),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final result = _result;
    final scheme = Theme.of(context).colorScheme;
    if (result == null) {
      return Center(
        child: Text(
          'Enter an agent address to begin.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
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
                style: TextStyle(color: scheme.error)),
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
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
