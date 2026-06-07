import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../preview/preview.dart';
import '../transfers/transfer_state.dart';

/// Bottom sheet showing detailed metadata for a single file, with rename,
/// delete, and download actions.
class MetaSheet extends ConsumerStatefulWidget {
  const MetaSheet({
    super.key,
    required this.entry,
    required this.host,
    required this.client,
  });

  final Entry entry;
  final Host host;
  final AgentClient client;

  @override
  ConsumerState<MetaSheet> createState() => _MetaSheetState();
}

class _MetaSheetState extends ConsumerState<MetaSheet> {
  late Entry _entry;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _refreshMeta();
  }

  Future<void> _refreshMeta() async {
    try {
      final fresh = await widget.client.meta(widget.entry.path);
      if (mounted) setState(() => _entry = fresh);
    } catch (_) {
      // Use cached entry on failure
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (_, controller) => Padding(
        padding: const EdgeInsets.all(16),
        child: CustomScrollView(
          controller: controller,
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context)),
            SliverList(
              delegate: SliverChildListDelegate([
                const Divider(),
                _row('Path', _entry.path),
                if (_entry.size != null) _row('Size', _formatSize(_entry.size)),
                if (_entry.mimeType != null) _row('Type', _entry.mimeType!),
                if (_entry.mode != null) _row('Permissions', _entry.mode!),
                if (_entry.modified != null)
                  _row('Modified', _entry.modified!.toLocal().toString()),
                if (_entry.created != null)
                  _row('Created', _entry.created!.toLocal().toString()),
                _row('Symlink', _entry.isSymlink ? 'Yes' : 'No'),
                const SizedBox(height: 16),
                _buildActions(context),
                const SizedBox(height: 32),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Icon(
          _entry.isDir ? Icons.folder : Icons.insert_drive_file,
          size: 40,
          color: _entry.isDir ? Colors.amber : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(_entry.name,
              style: Theme.of(context).textTheme.titleLarge,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _row(String label, String? value) {
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (!_entry.isDir && isPreviewable(_entry))
          FilledButton.icon(
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Preview'),
            onPressed: () => _preview(context),
          ),
        if (!_entry.isDir)
          FilledButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Download'),
            onPressed: () => _download(context),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.drive_file_rename_outline),
          label: const Text('Rename'),
          onPressed: () => _rename(context),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => _delete(context),
        ),
      ],
    );
  }

  Future<void> _preview(BuildContext context) async {
    await openPreview(
      context,
      entry: _entry,
      host: widget.host,
      client: widget.client,
    );
  }

  Future<void> _download(BuildContext context) async {
    final dir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final localPath = '${dir.path}/${_entry.name}';
    ref.read(transferQueueProvider.notifier).enqueue(
          TransferTask.download(
            remotePath: _entry.path,
            localPath: localPath,
            host: widget.host,
          ),
        );
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading ${_entry.name}…')),
      );
    }
  }

  Future<void> _rename(BuildContext context) async {
    final ctrl = TextEditingController(text: _entry.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Rename')),
        ],
      ),
    );
    if (newName == null || newName == _entry.name || !context.mounted) return;
    try {
      final parent = _parentPath(_entry.path);
      final dst = '$parent/$newName';
      final updated = await widget.client.rename(_entry.path, dst);
      if (mounted) setState(() => _entry = updated);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Renamed to $newName')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete "${_entry.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await widget.client.delete([_entry.path]);
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted ${_entry.name}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  String _parentPath(String path) {
    final sep = path.contains('/') ? '/' : r'\';
    final idx = path.lastIndexOf(sep);
    return idx <= 0 ? sep : path.substring(0, idx);
  }
}

String _formatSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
