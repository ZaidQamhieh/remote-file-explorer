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

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        // Summary header
        Text(
          '${result.totalFiles} files · ${formatSize(result.totalSize)}',
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: Spacing.md),

        // Stacked bar chart
        SizedBox(
          height: 32,
          child: CustomPaint(
            painter: _StackedBarPainter(
              segments:
                  sorted
                      .map(
                        (e) => _BarSegment(
                          ext: e.key,
                          bytes: e.value,
                          color: colorFor(categoryFor(e.key)),
                        ),
                      )
                      .toList(),
              totalBytes: result.totalSize,
              selectedExt: selectedExt,
            ),
            size: const Size(double.infinity, 32),
          ),
        ),
        const SizedBox(height: Spacing.lg),

        // Category legend (compact row)
        Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.xs,
          children: [
            for (final cat in FileCategory.values)
              if (_categoryPresent(cat, sorted)) _LegendChip(category: cat),
          ],
        ),
        const SizedBox(height: Spacing.md),

        // Detail list
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

  bool _categoryPresent(FileCategory cat, List<MapEntry<String, int>> sorted) {
    return sorted.any((e) => categoryFor(e.key) == cat);
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.category});
  final FileCategory category;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: colorFor(category),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          categoryLabel(category),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

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

    return Material(
      color:
          selected
              ? scheme.primaryContainer.withValues(alpha: 0.3)
              : Colors.transparent,
      borderRadius: Radii.smR,
      child: InkWell(
        borderRadius: Radii.smR,
        onTap: onTap,
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

// ---------------------------------------------------------------------------
// Custom painter for the stacked horizontal bar
// ---------------------------------------------------------------------------

class _BarSegment {
  const _BarSegment({
    required this.ext,
    required this.bytes,
    required this.color,
  });

  final String ext;
  final int bytes;
  final Color color;
}

class _StackedBarPainter extends CustomPainter {
  _StackedBarPainter({
    required this.segments,
    required this.totalBytes,
    this.selectedExt,
  });

  final List<_BarSegment> segments;
  final int totalBytes;
  final String? selectedExt;

  @override
  void paint(Canvas canvas, Size size) {
    if (totalBytes == 0 || segments.isEmpty) return;

    final radius = Radius.circular(Radii.sm);
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.clipRRect(rrect);

    var x = 0.0;
    for (final seg in segments) {
      final w = (seg.bytes / totalBytes) * size.width;
      if (w < 0.5) continue; // skip sub-pixel segments

      final paint =
          Paint()
            ..color =
                selectedExt == null || selectedExt == seg.ext
                    ? seg.color
                    : seg.color.withValues(alpha: 0.3);

      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      x += w;
    }
  }

  @override
  bool shouldRepaint(_StackedBarPainter old) =>
      old.selectedExt != selectedExt ||
      old.totalBytes != totalBytes ||
      old.segments.length != segments.length;
}
