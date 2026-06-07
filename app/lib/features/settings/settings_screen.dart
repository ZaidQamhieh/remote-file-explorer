import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/agent_settings.dart';
import '../../core/models/device.dart';
import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
import '../../core/ui/feedback.dart';
import 'update_tile.dart';

/// Per-host settings: read-only mode, folder jail, paired devices, agent name.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, required this.host});
  final Host host;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AgentClient? _client;
  AgentSettings? _settings;
  List<Device> _devices = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = await ref.read(hostStoreProvider.future);
      final token = await store.getToken(widget.host.id);
      final client = AgentClient(widget.host, deviceToken: token);
      final settings = await client.getSettings();
      final devices = await client.listDevices();
      setState(() {
        _client = client;
        _settings = settings;
        _devices = devices;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _patch(
      {bool? readOnly, List<String>? roots, String? name, String? successMsg}) async {
    final client = _client;
    if (client == null) return;
    final prev = _settings;
    // Optimistic update.
    setState(() {
      _settings = _settings?.copyWith(
        readOnly: readOnly,
        roots: roots,
        agentName: name,
      );
    });
    try {
      final updated = await client.updateSettings(
        readOnly: readOnly,
        roots: roots,
        agentName: name,
      );
      setState(() => _settings = updated);
      if (mounted && successMsg != null) showSuccess(context, successMsg);
    } catch (e) {
      setState(() => _settings = prev); // rollback
      if (mounted) showError(context, 'Update failed: $e');
    }
  }

  Future<void> _revoke(Device d) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.revokeDevice(d.id);
      await _load();
      if (mounted) showSuccess(context, 'Revoked "${d.label}"');
    } catch (e) {
      if (mounted) showError(context, 'Revoke failed: $e');
    }
  }

  Future<void> _addRoot() async {
    final ctrl = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add allowed folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '/home/me/Documents'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (path != null && path.isNotEmpty) {
      final roots = [...?_settings?.roots, path];
      await _patch(roots: roots, successMsg: 'Added $path');
    }
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _settings?.agentName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename agent'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await _patch(name: name, successMsg: 'Renamed to $name');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final s = _settings!;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'This phone has full control of the host. Anyone with access '
                'to it can change these settings and reach allowed folders.',
              ),
            ),
          ),
        ),
        ListTile(
          title: const Text('Agent name'),
          subtitle: Text(s.agentName),
          trailing: const Icon(Icons.edit),
          onTap: _editName,
        ),
        SwitchListTile(
          title: const Text('Read-only mode'),
          subtitle: Text(s.readOnly
              ? 'Writes are rejected'
              : 'This phone can modify files'),
          value: s.readOnly,
          onChanged: (v) => _patch(readOnly: v),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Allowed folders',
                  style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                  icon: const Icon(Icons.add), onPressed: _addRoot),
            ],
          ),
        ),
        if (s.roots.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('All folders allowed'),
          )
        else
          ...s.roots.map((r) => ListTile(
                dense: true,
                title: Text(r),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => _patch(
                    roots: s.roots.where((x) => x != r).toList(),
                    successMsg: 'Removed $r',
                  ),
                ),
              )),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Paired devices',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        ..._devices.map((d) => ListTile(
              leading: Icon(d.revoked
                  ? Icons.phonelink_erase
                  : Icons.smartphone),
              title: Text(d.current ? '${d.label} (this phone)' : d.label),
              subtitle: Text(d.revoked
                  ? 'Revoked'
                  : 'Last seen ${d.lastSeen.toLocal()}'),
              trailing: (d.current || d.revoked)
                  ? null
                  : TextButton(
                      onPressed: () => _revoke(d),
                      child: const Text('Revoke'),
                    ),
            )),
        const Divider(),
        UpdateTile(host: widget.host),
        const SizedBox(height: 24),
      ],
    );
  }
}
