/// Duplicate file finder screen.
///
/// Recursively collects all files under a root path via the agent's paginated
/// listing API, hashes them in batches with `batchChecksums`, and groups paths
/// that share a checksum. Results are sorted largest-waste-first.
library;

import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/entry_leading.dart'
    show archiveExtensions, docExtensions, imageExtensions, videoExtensions;
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/gradient_blob_hero.dart';
import '../../core/ui/gradient_button.dart';
import '../../core/ui/grouped_card.dart' show SectionLabel;
import '../../core/ui/pressable.dart';
import '../../core/ui/screen_header.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// One duplicate group: the checksum they share, plus every path with that
/// hash (largest-group-first order preserved from [groupDuplicates]).
class _DupGroup {
  _DupGroup(this.hash, this.paths);
  final String hash;
  final List<String> paths;
}

/// Icon + tint for a duplicate row, keyed off the file extension (no MIME
/// type available from `batchChecksums`) — mirrors `entry_leading.dart`'s
/// category tint palette so a duplicate photo still reads as violet, a PDF
/// as red, etc., instead of every row rendering the same neutral icon.
({IconData icon, Color? color}) _rowIconFor(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  if (imageExtensions.contains(ext) || videoExtensions.contains(ext)) {
    return (icon: LucideIcons.image, color: Brand.accent);
  }
  if (archiveExtensions.contains(ext)) {
    return (icon: LucideIcons.fileArchive, color: Brand.amber);
  }
  if (ext == 'pdf') return (icon: LucideIcons.fileText, color: Brand.red);
  if (docExtensions.contains(ext)) {
    return (icon: LucideIcons.fileText, color: Brand.seed);
  }
  return (icon: LucideIcons.file, color: null);
}

class DupFinderScreen extends StatefulWidget {
  const DupFinderScreen({
    super.key,
    required this.hostId,
    required this.path,
    required this.client,
  });

  final String hostId;
  final String path;
  final AgentClient client;

  @override
  State<DupFinderScreen> createState() => _DupFinderScreenState();
}

class _DupFinderScreenState extends State<DupFinderScreen> {
  List<_DupGroup>? _groups;
  Map<String, int>? _sizes;
  String? _error;
  bool _scanning = false;
  bool _deleting = false;
  int _filesScanned = 0;

  /// Paths currently marked for deletion — every path but the first
  /// ("kept") one in each group is pre-selected, matching the mockup's
  /// static illustration (first row badged "Keep", the rest checked).
  Set<String> _toDelete = {};

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
      _filesScanned = 0;
    });
    try {
      final paths = <String>[];
      final sizes = <String, int>{};
      await _collectFiles(widget.path, paths, sizes);
      if (!mounted) return;
      setState(() => _filesScanned = paths.length);

      if (paths.isEmpty) {
        setState(() {
          _scanning = false;
          _groups = [];
          _sizes = sizes;
        });
        return;
      }

      // Batch checksum in chunks of 500
      final allHashes = <String, String>{};
      for (var i = 0; i < paths.length; i += 500) {
        final chunk = paths.sublist(i, (i + 500).clamp(0, paths.length));
        final hashes = await widget.client.batchChecksums(chunk);
        if (!mounted) return;
        allHashes.addAll(hashes);
      }

      // Group by hash
      final byHash = <String, List<String>>{};
      for (final entry in allHashes.entries) {
        byHash.putIfAbsent(entry.value, () => []).add(entry.key);
      }
      final groups =
          byHash.entries.where((e) => e.value.length > 1).toList()
            ..sort((a, b) {
              final sA = sizes[a.value.first] ?? 0;
              final sB = sizes[b.value.first] ?? 0;
              return sB.compareTo(sA); // largest first
            });

      setState(() {
        _groups = [for (final e in groups) _DupGroup(e.key, e.value)];
        _sizes = sizes;
        _scanning = false;
        _toDelete = {
          for (final e in groups)
            for (final p in e.value.skip(1)) p,
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = humanizeError(e);
        _scanning = false;
      });
    }
  }

  void _toggleSelect(String path) {
    setState(() {
      if (!_toDelete.remove(path)) _toDelete.add(path);
    });
  }

  Future<void> _deleteSelected() async {
    if (_toDelete.isEmpty || _deleting) return;
    setState(() => _deleting = true);
    try {
      final freed = _toDelete.fold<int>(0, (sum, p) => sum + (_sizes?[p] ?? 0));
      final deleted = _toDelete.toList();
      await widget.client.delete(deleted);
      if (!mounted) return;
      setState(() {
        for (final group in _groups!) {
          group.paths.removeWhere(deleted.contains);
        }
        _groups!.removeWhere((g) => g.paths.length < 2);
        _toDelete = {};
        _deleting = false;
      });
      if (mounted) {
        showSuccess(
          context,
          'Deleted ${deleted.length} duplicates — ${formatSize(freed)} freed',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showError(context, humanizeError(e));
    }
  }

  /// Recursively collects every file under [path], fully paging through each
  /// directory's listing (PR-33) — a directory with more entries than one
  /// page used to silently contribute only its first page, so results could
  /// be incomplete without any indication.
  Future<void> _collectFiles(
    String path,
    List<String> paths,
    Map<String, int> sizes,
  ) async {
    String? cursor;
    do {
      final listing = await widget.client.list(path, cursor: cursor);
      for (final entry in listing.entries) {
        if (entry.isDir) {
          await _collectFiles(entry.path, paths, sizes);
        } else {
          paths.add(entry.path);
          if (entry.size != null) sizes[entry.path] = entry.size!;
        }
      }
      cursor = listing.nextCursor;
    } while (cursor != null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: const ScreenHeader('Duplicate Finder'),
      ),
      body:
          _scanning
              ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('Scanning $_filesScanned files...'),
                  ],
                ),
              )
              : _error != null
              ? Center(child: Text('Error: $_error'))
              : _groups == null
              ? Center(
                child: GradientButton(
                  onPressed: _scan,
                  child: const Text('Scan for Duplicates'),
                ),
              )
              : _groups!.isEmpty
              ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    GradientBlobHero(icon: LucideIcons.badgeCheck, size: 120),
                    SizedBox(height: 12),
                    Text('No duplicates found'),
                  ],
                ),
              )
              : _buildResults(),
    );
  }

  Widget _buildResults() {
    final scheme = Theme.of(context).colorScheme;
    final totalWaste = _groups!.fold<int>(0, (sum, g) {
      final size = _sizes?[g.paths.first] ?? 0;
      return sum + size * (g.paths.length - 1);
    });
    return Column(
      children: [
        // Mockup's two-stat summary card (groups / reclaimable space).
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            Spacing.sm,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: Radii.cardR,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(value: '${_groups!.length}', label: 'groups'),
                _StatCell(
                  value: formatSize(totalWaste),
                  label: 'reclaimable',
                  valueColor: Brand.online,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final group in _groups!) ...[
                SectionLabel(
                  '${group.paths.first.split('/').last} · '
                  '${group.paths.length} copies · '
                  '${group.hash.length > 4 ? group.hash.substring(0, 4) : group.hash}…',
                ),
                for (final (i, path) in group.paths.indexed)
                  _DupRow(
                    path: path,
                    size: _sizes?[path],
                    kept: i == 0,
                    selected: _toDelete.contains(path),
                    onToggle: i == 0 ? null : () => _toggleSelect(path),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.md,
                  Spacing.md,
                  Spacing.lg,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    onPressed:
                        _toDelete.isEmpty || _deleting ? null : _deleteSelected,
                    child: Text(
                      'Delete ${_toDelete.length} selected duplicates',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One cell of the duplicate-finder's summary stat card.
class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label, this.valueColor});

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontFamily: 'JetBrains Mono',
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// One duplicate-file row: the mockup's `.row` with a colored `.row-icon`,
/// plus either a green "Keep" `.badge` (the group's first/kept copy, not
/// selectable) or a `.sel-box` checkbox toggling deletion.
class _DupRow extends StatelessWidget {
  const _DupRow({
    required this.path,
    required this.size,
    required this.kept,
    required this.selected,
    required this.onToggle,
  });

  final String path;
  final int? size;
  final bool kept;
  final bool selected;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spec = _rowIconFor(path);
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      child: Row(
        children: [
          if (!kept) ...[
            _SelBox(checked: selected),
            const SizedBox(width: Spacing.sm),
          ],
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (spec.color ?? scheme.onSurfaceVariant).withValues(
                alpha: 0.14,
              ),
              borderRadius: Radii.smR,
            ),
            alignment: Alignment.center,
            child: Icon(spec.icon, size: 18, color: spec.color),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  path,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  formatSize(size),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (kept)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Brand.online.withValues(alpha: 0.14),
                borderRadius: Radii.stadiumR,
              ),
              child: Text(
                'Keep',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Brand.online,
                ),
              ),
            ),
        ],
      ),
    );
    return onToggle == null ? row : Pressable(onTap: onToggle, child: row);
  }
}

/// The mockup's `.sel-box`: 20x20, 6px radius, `border-strong` outline,
/// filled `--primary` + white check when checked.
class _SelBox extends StatelessWidget {
  const _SelBox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: checked ? Brand.seed : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: checked ? Brand.seed : scheme.outlineVariant,
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child:
          checked
              ? const Icon(LucideIcons.check, size: 13, color: Colors.white)
              : null,
    );
  }
}

/// Compute wasted bytes across duplicate groups.
///
/// Exported for unit testing. Each group contributes
/// `fileSize * (copies - 1)` bytes of waste.
int computeWaste(List<List<String>> groups, Map<String, int> sizes) {
  return groups.fold<int>(0, (sum, g) {
    final size = sizes[g.first] ?? 0;
    return sum + size * (g.length - 1);
  });
}

/// Group a path-to-hash map into duplicate groups (2+ paths sharing a hash),
/// sorted by descending file size.
///
/// Exported for unit testing.
List<List<String>> groupDuplicates(
  Map<String, String> hashes,
  Map<String, int> sizes,
) {
  final byHash = <String, List<String>>{};
  for (final entry in hashes.entries) {
    byHash.putIfAbsent(entry.value, () => []).add(entry.key);
  }
  return byHash.values.where((g) => g.length > 1).toList()..sort((a, b) {
    final sA = sizes[a.first] ?? 0;
    final sB = sizes[b.first] ?? 0;
    return sB.compareTo(sA);
  });
}
