import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/ui/feedback.dart';
import 'image_preview.dart';
import 'pdf_preview.dart';
import 'preview_actions.dart';
import 'preview_image_cache.dart';
import 'text_preview.dart';
import 'video_preview.dart';

enum _PreviewKind { image, pdf, video, text, none }

const Set<String> _textExtensions = {
  'txt', 'md', 'markdown', 'json', 'yaml', 'yml', 'xml', 'csv', 'tsv', 'log',
  'ini', 'cfg', 'conf', 'toml', 'env',
  // source code
  'dart', 'go', 'py', 'js', 'jsx', 'ts', 'tsx', 'java', 'kt', 'kts', 'c', 'h',
  'cpp', 'hpp', 'cc', 'cs', 'rs', 'rb', 'php', 'swift', 'sh', 'bash', 'zsh',
  'sql', 'gradle', 'properties', 'gitignore', 'dockerfile', 'makefile',
  'html', 'htm', 'css', 'scss', 'less', 'vue', 'svelte',
};

const Set<String> _imageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'bmp',
  'webp',
  'heic',
  'heif',
};

const Set<String> _videoExtensions = {
  'mp4',
  'mov',
  'mkv',
  'avi',
  'webm',
  'm4v',
  '3gp',
};

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

_PreviewKind _kindOf(Entry entry) {
  final mime = entry.mimeType?.toLowerCase();
  final ext = _extensionOf(entry.name);

  if (mime != null) {
    if (mime.startsWith('image/')) return _PreviewKind.image;
    if (mime == 'application/pdf') return _PreviewKind.pdf;
    if (mime.startsWith('video/')) return _PreviewKind.video;
    if (mime.startsWith('text/')) return _PreviewKind.text;
    if (mime == 'application/json' ||
        mime == 'application/xml' ||
        mime == 'application/x-yaml' ||
        mime.endsWith('+json') ||
        mime.endsWith('+xml')) {
      return _PreviewKind.text;
    }
  }

  // Fall back to file extension when the mime type is missing/unhelpful.
  if (_imageExtensions.contains(ext)) return _PreviewKind.image;
  if (ext == 'pdf') return _PreviewKind.pdf;
  if (_videoExtensions.contains(ext)) return _PreviewKind.video;
  if (_textExtensions.contains(ext)) return _PreviewKind.text;

  return _PreviewKind.none;
}

/// Whether [entry] has a known preview viewer (used to decide whether to
/// show a "Preview" action for it).
bool isPreviewable(Entry entry) {
  if (entry.isDir) return false;
  return _kindOf(entry) != _PreviewKind.none;
}

/// Whether [entry]'s viewer is the image viewer — the only kind that uses a
/// tile→preview [Hero] and gets neighbour byte-preloading in the pager.
bool _isImage(Entry entry) => _kindOf(entry) == _PreviewKind.image;

/// Filters [siblings] down to the previewable ones (in their original order)
/// and locates [entry]'s index within that filtered list.
///
/// Pure + side-effect-free so it can be unit-tested directly. Returns the
/// filtered list and the start index. If [entry] isn't a previewable member of
/// [siblings] (or [siblings] is empty), the index is `-1` — callers treat that
/// as "no pager, fall back to the single-entry viewer".
({List<Entry> entries, int index}) previewableSiblings(
  List<Entry> siblings,
  Entry entry,
) {
  final filtered = siblings.where(isPreviewable).toList(growable: false);
  // Match by path (the unique key) rather than identity — the tapped entry may
  // be a freshly-fetched copy of the one in the listing.
  final index = filtered.indexWhere((e) => e.path == entry.path);
  return (entries: filtered, index: index);
}

/// Builds the per-type viewer widget for [entry]. When [chromeless] is set the
/// viewer omits its own app bar so the [PreviewPager] can overlay one shared
/// top bar; for images, [host] also drives the [Hero] tag.
Widget? _viewerFor(
  Entry entry, {
  required Host host,
  required AgentClient client,
  bool chromeless = false,
}) {
  switch (_kindOf(entry)) {
    case _PreviewKind.image:
      return ImagePreviewScreen(
        entry: entry,
        client: client,
        chromeless: chromeless,
        heroTag: imagePreviewHeroTag(host.id, entry.path),
      );
    case _PreviewKind.pdf:
      return PdfPreviewScreen(
        entry: entry,
        client: client,
        chromeless: chromeless,
      );
    case _PreviewKind.video:
      return VideoPreviewScreen(
        entry: entry,
        client: client,
        chromeless: chromeless,
      );
    case _PreviewKind.text:
      return TextPreviewScreen(
        entry: entry,
        client: client,
        chromeless: chromeless,
      );
    case _PreviewKind.none:
      return null;
  }
}

/// Opens the appropriate in-app preview viewer for [entry], based on its
/// MIME type (falling back to file extension). Shows a snackbar if there's
/// no preview available for this file type.
///
/// When [siblings] (typically the explorer's visible listing) is supplied and
/// contains [entry], a swipeable [PreviewPager] is pushed instead: the user can
/// swipe between *previewable* siblings, with adjacent images preloaded so the
/// swap feels instant. When [siblings] is null/empty or [entry] isn't among the
/// previewable ones, the original single-entry behaviour is preserved exactly.
///
/// [onChanged] is invoked after a destructive action (delete) so the caller can
/// refresh its listing.
///
/// All preview content is fetched through [client] — the pinned,
/// authenticated `AgentClient` — never via plain network requests, since the
/// agent uses a self-signed certificate and bearer-token auth.
Future<void> openPreview(
  BuildContext context, {
  required Entry entry,
  required Host host,
  required AgentClient client,
  List<Entry>? siblings,
  VoidCallback? onChanged,
}) async {
  if (entry.isDir) return;

  if (_kindOf(entry) == _PreviewKind.none) {
    showInfo(context, 'No preview available for this file type');
    return;
  }

  // Try the swipeable pager path when a listing was provided.
  if (siblings != null && siblings.isNotEmpty) {
    final (entries: filtered, index: start) = previewableSiblings(
      siblings,
      entry,
    );
    if (start >= 0 && filtered.length > 1) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => PreviewPager(
                entries: filtered,
                initialIndex: start,
                host: host,
                client: client,
                onChanged: onChanged,
              ),
        ),
      );
      return;
    }
  }

  // Single-entry fallback — unchanged from the original behaviour.
  final screen = _viewerFor(entry, host: host, client: client);
  if (screen == null) {
    showInfo(context, 'No preview available for this file type');
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

/// A swipeable preview host: a `PageView` over a list of previewable
/// [entries], each rendered by its per-type viewer (chromeless), under a single
/// shared [PreviewTopBar] driven by the current page's entry.
///
/// Swiping pages between sibling files; when a page settles, the immediate
/// neighbours' (±1) image bytes are preloaded so the next swipe shows instantly.
/// Only images are preloaded — pdf/video are too heavy to warm speculatively.
class PreviewPager extends StatefulWidget {
  const PreviewPager({
    super.key,
    required this.entries,
    required this.initialIndex,
    required this.host,
    required this.client,
    this.onChanged,
  });

  final List<Entry> entries;
  final int initialIndex;
  final Host host;
  final AgentClient client;
  final VoidCallback? onChanged;

  @override
  State<PreviewPager> createState() => _PreviewPagerState();
}

class _PreviewPagerState extends State<PreviewPager> {
  late final PageController _controller;
  late List<Entry> _entries;
  late int _index;

  @override
  void initState() {
    super.initState();
    _entries = List.of(widget.entries);
    _index = widget.initialIndex.clamp(0, _entries.length - 1);
    _controller = PageController(initialPage: _index);
    WidgetsBinding.instance.addPostFrameCallback((_) => _preloadNeighbours());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Warms the ±1 neighbours' image bytes so swiping is instant. Bounded to the
  /// immediate neighbours and to images only.
  void _preloadNeighbours() {
    for (final i in [_index - 1, _index + 1]) {
      if (i < 0 || i >= _entries.length) continue;
      final e = _entries[i];
      if (_isImage(e)) {
        PreviewImageCache.instance.preload(widget.client, e.path);
      }
    }
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    _preloadNeighbours();
  }

  /// Drops the entry at [_index] from the pager after a delete. If it was the
  /// last remaining page, pops the whole pager.
  void _onDeletedCurrent() {
    if (_entries.length <= 1) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _entries.removeAt(_index);
      if (_index >= _entries.length) _index = _entries.length - 1;
    });
    // Keep the controller in sync with the collapsed list.
    _controller.jumpToPage(_index);
  }

  @override
  Widget build(BuildContext context) {
    final current = _entries[_index];
    final onDark = _isImage(current) || _kindOf(current) == _PreviewKind.video;

    return Scaffold(
      backgroundColor: onDark ? Colors.black : null,
      extendBodyBehindAppBar: onDark,
      appBar: PreviewTopBar(
        onDark: onDark,
        actions: PreviewActions(
          entry: current,
          host: widget.host,
          client: widget.client,
          onDeleted: widget.onChanged,
        ),
        onDelete: _onDeletedCurrent,
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: _entries.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, i) {
          // KeyedSubtree so each page's per-type State is preserved as the user
          // pages back and forth (e.g. a video keeps its controller).
          final e = _entries[i];
          return KeyedSubtree(
            key: ValueKey(e.path),
            child:
                _viewerFor(
                  e,
                  host: widget.host,
                  client: widget.client,
                  chromeless: true,
                ) ??
                const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
