import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/archive_entry.dart';
import '../../core/models/entry.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/pressable.dart';
import 'preview_common.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Preview screen for archive files (zip, tar, etc.). Lists the archive's
/// contents (files and directories) fetched via [AgentClient.archiveList],
/// with drill-down into directories by tapping folder entries.
class ArchivePreviewScreen extends StatefulWidget {
  const ArchivePreviewScreen({
    super.key,
    required this.entry,
    required this.client,
    this.chromeless = false,
  });

  final Entry entry;
  final AgentClient client;
  final bool chromeless;

  @override
  State<ArchivePreviewScreen> createState() => _ArchivePreviewScreenState();
}

class _ArchivePreviewScreenState extends State<ArchivePreviewScreen> {
  List<ArchiveEntry>? _entries;
  String? _error;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await widget.client.archiveList(widget.entry.path);
      if (mounted) setState(() => _entries = entries);
    } catch (e) {
      if (mounted) setState(() => _error = humanizeError(e));
    }
  }

  List<ArchiveEntry> get _filtered {
    if (_entries == null) return [];
    if (_filter.isEmpty) return _entries!;
    return _entries!.where((e) => e.path.startsWith(_filter)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_entries == null && _error == null) {
      body = const PreviewLoading(message: 'Loading archive contents…');
    } else if (_error != null) {
      body = PreviewError(
        message: 'Could not read archive: $_error',
        onRetry: () {
          setState(() {
            _error = null;
            _entries = null;
          });
          _load();
        },
      );
    } else {
      body = _buildList(context);
    }

    if (widget.chromeless) return body;

    return PreviewScaffold(
      title: widget.entry.name,
      chromeless: false,
      actions: [
        if (_entries != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${_entries!.length} ${_entries!.length == 1 ? 'entry' : 'entries'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
      ],
      body: Column(
        children: [
          if (_filter.isNotEmpty)
            Builder(
              builder: (context) {
                final scheme = Theme.of(context).colorScheme;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.cornerDownRight,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '/$_filter',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Pressable(
                        onTap: () => setState(() => _filter = ''),
                        child: Icon(
                          LucideIcons.x,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final entries = _filtered;
    if (entries.isEmpty) {
      return const Center(child: Text('Empty archive'));
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      itemCount: entries.length,
      itemBuilder: (ctx, i) {
        final e = entries[i];
        final color = e.isDir ? Brand.amber : scheme.onSurfaceVariant;
        return Pressable(
          onTap: e.isDir ? () => setState(() => _filter = e.path) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color:
                        e.isDir
                            ? Brand.amber.withValues(alpha: 0.14)
                            : scheme.surfaceContainerHigh,
                    borderRadius: Radii.smR,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    e.isDir ? LucideIcons.folder : LucideIcons.file,
                    size: 19,
                    color: color,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e.path,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (!e.isDir) ...[
                        const SizedBox(height: 2),
                        Text(
                          formatSize(e.size),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
