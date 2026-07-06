/// Duplicate file finder screen.
///
/// Recursively collects all files under a root path via the agent's paginated
/// listing API, hashes them in batches with `batchChecksums`, and groups paths
/// that share a checksum. Results are sorted largest-waste-first.
library;

import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';

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
      setState(() {
        _error = humanizeError(e);
        _scanning = false;
      });
    }
  }

  Future<void> _collectFiles(
    String path,
    List<String> paths,
    Map<String, int> sizes,
  ) async {
    final listing = await widget.client.list(path);
    for (final entry in listing.entries) {
      if (entry.isDir) {
        await _collectFiles(entry.path, paths, sizes);
      } else {
        paths.add(entry.path);
        if (entry.size != null) sizes[entry.path] = entry.size!;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Duplicate Finder')),
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
              ? const Center(child: Text('No duplicates found'))
              : _buildResults(),
    );
  }

  Widget _buildResults() {
    final totalWaste = _groups!.fold<int>(0, (sum, g) {
      final size = _sizes?[g.first] ?? 0;
      return sum + size * (g.length - 1);
    });
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '${_groups!.length} duplicate groups (${formatSize(totalWaste)} wasted)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _groups!.length,
            itemBuilder: (ctx, i) {
              final group = _groups![i];
              final size = _sizes?[group.first] ?? 0;
              return ExpansionTile(
                title: Text(
                  '${group.length} copies (${formatSize(size)} each)',
                ),
                children: [
                  for (final path in group)
                    ListTile(
                      dense: true,
                      title: Text(path, style: const TextStyle(fontSize: 13)),
                    ),
                ],
              );
            },
          ),
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
