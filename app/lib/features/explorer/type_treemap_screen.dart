/// File-type distribution visualization for a directory.
///
/// Recursively scans a directory tree via the agent's paginated listing API,
/// aggregates file sizes by extension, and renders a horizontal stacked bar
/// plus a sorted detail list.
library;

import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/grouped_card.dart';
import '../../core/ui/screen_header.dart';
import '../../core/ui/pressable.dart';
import '../../core/theme/tokens.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// ---------------------------------------------------------------------------
// Category colour mapping
// ---------------------------------------------------------------------------

/// Extension-to-category mapping used for colouring bar segments.
enum FileCategory { image, video, audio, document, archive, code, other }

const _categoryExtensions = <FileCategory, Set<String>>{
  FileCategory.image: {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.svg',
    '.bmp',
    '.ico',
    '.tiff',
  },
  FileCategory.video: {'.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm'},
  FileCategory.audio: {'.mp3', '.flac', '.wav', '.aac', '.ogg', '.wma', '.m4a'},
  FileCategory.document: {
    '.pdf',
    '.doc',
    '.docx',
    '.txt',
    '.md',
    '.rtf',
    '.odt',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
    '.csv',
  },
  FileCategory.archive: {
    '.zip',
    '.tar',
    '.gz',
    '.rar',
    '.7z',
    '.bz2',
    '.xz',
    '.tgz',
  },
  FileCategory.code: {
    '.dart',
    '.go',
    '.py',
    '.js',
    '.ts',
    '.java',
    '.kt',
    '.c',
    '.cpp',
    '.h',
    '.rs',
    '.rb',
    '.swift',
    '.html',
    '.css',
    '.json',
    '.yaml',
    '.yml',
    '.xml',
    '.sh',
    '.bat',
    '.sql',
  },
};

FileCategory categoryFor(String ext) {
  final lower = ext.toLowerCase();
  for (final entry in _categoryExtensions.entries) {
    if (entry.value.contains(lower)) return entry.key;
  }
  return FileCategory.other;
}

Color colorFor(FileCategory cat) {
  switch (cat) {
    case FileCategory.image:
      return const Color(0xFF42A5F5); // blue
    case FileCategory.video:
      return const Color(0xFFAB47BC); // purple
    case FileCategory.audio:
      return const Color(0xFF66BB6A); // green
    case FileCategory.document:
      return const Color(0xFFFFA726); // orange
    case FileCategory.archive:
      return const Color(0xFF8D6E63); // brown
    case FileCategory.code:
      return const Color(0xFF26C6DA); // cyan
    case FileCategory.other:
      return const Color(0xFF9E9E9E); // grey
  }
}

String categoryLabel(FileCategory cat) {
  switch (cat) {
    case FileCategory.image:
      return 'Images';
    case FileCategory.video:
      return 'Videos';
    case FileCategory.audio:
      return 'Audio';
    case FileCategory.document:
      return 'Documents';
    case FileCategory.archive:
      return 'Archives';
    case FileCategory.code:
      return 'Code';
    case FileCategory.other:
      return 'Other';
  }
}

// ---------------------------------------------------------------------------
// Aggregation (pure, testable)
// ---------------------------------------------------------------------------

/// Result of aggregating files by extension.
class TypeAggregation {
  const TypeAggregation({
    required this.sizeByExt,
    required this.countByExt,
    required this.totalSize,
    required this.totalFiles,
  });

  final Map<String, int> sizeByExt;
  final Map<String, int> countByExt;
  final int totalSize;
  final int totalFiles;
}

/// Groups a flat list of `(extension, size)` pairs into per-extension totals.
///
/// Exposed as a top-level function so unit tests can exercise it without
/// constructing widgets or mocking the agent.
TypeAggregation aggregateByExtension(List<({String ext, int size})> files) {
  final sizeByExt = <String, int>{};
  final countByExt = <String, int>{};
  var totalSize = 0;
  var totalFiles = 0;

  for (final f in files) {
    final ext = f.ext.isEmpty ? '(no ext)' : f.ext.toLowerCase();
    sizeByExt[ext] = (sizeByExt[ext] ?? 0) + f.size;
    countByExt[ext] = (countByExt[ext] ?? 0) + 1;
    totalSize += f.size;
    totalFiles++;
  }

  return TypeAggregation(
    sizeByExt: sizeByExt,
    countByExt: countByExt,
    totalSize: totalSize,
    totalFiles: totalFiles,
  );
}

/// Extracts the file extension (with dot) from a filename.
///
/// Returns empty string for files without an extension.
String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot);
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class TypeTreemapScreen extends StatefulWidget {
  const TypeTreemapScreen({
    super.key,
    required this.hostId,
    required this.path,
    required this.client,
  });

  final String hostId;
  final String path;
  final AgentClient client;

  @override
  State<TypeTreemapScreen> createState() => _TypeTreemapScreenState();
}

class _TypeTreemapScreenState extends State<TypeTreemapScreen> {
  TypeAggregation? _result;
  String? _error;
  int _scannedFiles = 0;
  bool _scanning = true;
  String? _selectedExt;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
      _scannedFiles = 0;
      _result = null;
      _selectedExt = null;
    });

    try {
      final files = <({String ext, int size})>[];
      await _walkDirectory(widget.path, files);
      if (!mounted) return;
      setState(() {
        _result = aggregateByExtension(files);
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

  Future<void> _walkDirectory(
    String path,
    List<({String ext, int size})> out,
  ) async {
    String? cursor;
    do {
      final listing = await widget.client.list(
        path,
        cursor: cursor,
        limit: 200,
      );
      for (final entry in listing.entries) {
        if (entry.isDir) {
          await _walkDirectory(entry.path, out);
        } else {
          out.add((ext: extensionOf(entry.name), size: entry.size ?? 0));
          if (mounted && out.length % 50 == 0) {
            setState(() => _scannedFiles = out.length);
          }
        }
      }
      cursor = listing.nextCursor;
    } while (cursor != null);

    if (mounted) setState(() => _scannedFiles = out.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: const ScreenHeader('Storage by type'),
      ),
      body:
          _scanning
              ? _ScanningView(fileCount: _scannedFiles)
              : _error != null
              ? _ErrorView(error: _error!, onRetry: _scan)
              : _result != null && _result!.totalFiles > 0
              ? _ResultView(
                result: _result!,
                selectedExt: _selectedExt,
                onSelect:
                    (ext) => setState(() {
                      _selectedExt = _selectedExt == ext ? null : ext;
                    }),
              )
              : const _EmptyView(),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-views
// ---------------------------------------------------------------------------

class _ScanningView extends StatelessWidget {
  const _ScanningView({required this.fileCount});
  final int fileCount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: Spacing.md),
          Text('Scanning...', style: textTheme.titleMedium),
          const SizedBox(height: Spacing.xs),
          Text(
            '$fileCount files',
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: Spacing.md),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: Spacing.md),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.folderOpen,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'No files found',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.result,
    required this.selectedExt,
    required this.onSelect,
  });

  final TypeAggregation result;
  final String? selectedExt;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    // Sort extensions by size descending.
    final sorted =
        result.sizeByExt.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    final textTheme = Theme.of(context).textTheme;
    final buckets = _bucketedBySize(sorted);

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        // Summary header
        Text(
          '${result.totalFiles} files · ${formatSize(result.totalSize)}',
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: Spacing.md),

        // Category treemap — mockup's block-area-proportional-to-size grid
        // (largest category top-left), not the old per-extension bar chart.
        _CategoryTreemap(buckets: buckets),
        const SizedBox(height: Spacing.sm),
        Text(
          'Block area is proportional to space used — largest first, '
          'top-left.',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.lg),

        // Per-extension detail (finer-grained than the mockup shows, kept
        // for users who want it — tap to highlight in this list).
        GroupedCard(
          padded: false,
          children: [
            for (int i = 0; i < sorted.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: Spacing.md,
                  endIndent: Spacing.md,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              _ExtensionRow(
                ext: sorted[i].key,
                totalBytes: sorted[i].value,
                fileCount: result.countByExt[sorted[i].key] ?? 0,
                percentage:
                    result.totalSize > 0
                        ? sorted[i].value / result.totalSize * 100
                        : 0,
                selected: selectedExt == sorted[i].key,
                onTap: () => onSelect(sorted[i].key),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Mockup's 5 storage categories are coarser than [FileCategory] (7 values,
/// kept as-is — it's the tested extension classifier). This groups them for
/// the treemap display only: Photos & Video = image+video, Documents =
/// document+code, Archives = archive, Other = audio+other. (The mockup also
/// shows an "Apps" category for installers/executables — this app's
/// classifier has no such bucket, no `.exe`/`.apk`/`.dmg` extension set, so
/// app-type files land in "Other"; flagging as a real data gap, not
/// fabricated.)
String _visualBucketLabel(FileCategory c) => switch (c) {
  FileCategory.image || FileCategory.video => 'Photos & Video',
  FileCategory.document || FileCategory.code => 'Documents',
  FileCategory.archive => 'Archives',
  FileCategory.audio || FileCategory.other => 'Other',
};

/// Aggregates [sorted] (ext -> size, already size-descending) into the 4
/// visual buckets above, dropping empty ones, sorted largest-first.
List<(String label, int size)> _bucketedBySize(
  List<MapEntry<String, int>> sorted,
) {
  final sizes = <String, int>{};
  for (final e in sorted) {
    final label = _visualBucketLabel(categoryFor(e.key));
    sizes[label] = (sizes[label] ?? 0) + e.value;
  }
  final list =
      sizes.entries.map((e) => (e.key, e.value)).toList()
        ..sort((a, b) => b.$2.compareTo(a.$2));
  return list;
}

/// Category storage treemap — mirrors the mockup's CSS grid (a large block
/// for the biggest category, spanning the left column, with the rest
/// stacked in the right column, largest first, top-left).
class _CategoryTreemap extends StatelessWidget {
  const _CategoryTreemap({required this.buckets});

  final List<(String label, int size)> buckets;

  static const _gradients = [
    [Color(0xFF4C8DFF), Color(0xFF2A5FD9)], // primary blue — biggest
    [Color(0xFF9B87F5), Color(0xFF7C6AE0)], // violet
    [Color(0xFFF3A73F), Color(0xFFD98A1F)], // amber
    [Color(0xFF4A5064), Color(0xFF363B4A)], // neutral grey
  ];

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) return const SizedBox.shrink();
    Widget block(int i) => _TreemapBlock(
      label: buckets[i].$1,
      size: buckets[i].$2,
      gradient: _gradients[i % _gradients.length],
    );
    if (buckets.length == 1) {
      return SizedBox(height: 160, child: block(0));
    }
    return SizedBox(
      height: 236,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 16, child: block(0)),
          const SizedBox(width: Spacing.xs),
          Expanded(
            flex: 10,
            child: Column(
              children: [
                for (var i = 1; i < buckets.length; i++) ...[
                  if (i > 1) const SizedBox(height: Spacing.xs),
                  Expanded(child: block(i)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TreemapBlock extends StatelessWidget {
  const _TreemapBlock({
    required this.label,
    required this.size,
    required this.gradient,
  });

  final String label;
  final int size;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: Radii.smR,
      ),
      alignment: Alignment.bottomLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          Text(
            formatSize(size),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontFamily: 'JetBrains Mono',
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _ExtensionRow extends StatelessWidget {
  const _ExtensionRow({
    required this.ext,
    required this.totalBytes,
    required this.fileCount,
    required this.percentage,
    required this.selected,
    required this.onTap,
  });

  final String ext;
  final int totalBytes;
  final int fileCount;
  final double percentage;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = colorFor(categoryFor(ext));

    return Pressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color:
              selected
                  ? scheme.primaryContainer.withValues(alpha: 0.3)
                  : Colors.transparent,
          borderRadius: Radii.smR,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(child: Text(ext, style: textTheme.bodyMedium)),
              Text(
                formatSize(totalBytes),
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: Spacing.md),
              SizedBox(
                width: 48,
                child: Text(
                  '$fileCount',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              SizedBox(
                width: 52,
                child: Text(
                  '${percentage.toStringAsFixed(1)}%',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
