/// Duplicate file finder screen.
///
/// Recursively collects all files under a root path via the agent's paginated
/// listing API, hashes them in batches with `batchChecksums`, and groups paths
/// that share a checksum. Results are sorted largest-waste-first.
library;

import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/gradient_blob_hero.dart';
import '../../core/ui/grouped_card.dart' show SectionLabel;
import '../../core/ui/screen_header.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
  List<List<String>>? _groups;
  Map<String, int>? _sizes;
  String? _error;
  bool _scanning = false;
  int _filesScanned = 0;

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
      final dups =
          byHash.values.where((g) => g.length > 1).toList()..sort((a, b) {
            final sA = sizes[a.first] ?? 0;
            final sB = sizes[b.first] ?? 0;
            return sB.compareTo(sA); // largest first
          });

      setState(() {
        _groups = dups;
        _sizes = sizes;
        _scanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = humanizeError(e);
        _scanning = false;
      });
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
                child: FilledButton(
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
      final size = _sizes?[g.first] ?? 0;
      return sum + size * (g.length - 1);
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
              for (int g = 0; g < _groups!.length; g++) ...[
                SectionLabel(
                  '${_groups![g].length} copies '
                  '(${formatSize(_sizes?[_groups![g].first] ?? 0)} each)',
                ),
                for (final path in _groups![g])
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: Spacing.xs,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: Radii.smR,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            LucideIcons.file,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            path,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          formatSize(_sizes?[path]),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
              ],
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
