import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/ui/format.dart';
import 'preview_common.dart';
import 'preview_image_cache.dart';

/// Stable [Hero] tag for [entry]'s image, shared between the explorer tile/cell
/// thumbnail and the full-screen [ImagePreviewScreen] so the thumbnail flies
/// into the preview. Keyed by host + path so tags are unique across hosts and
/// don't collide between two files with the same name in different folders.
String imagePreviewHeroTag(String hostId, String path) =>
    'preview-$hostId-$path';

/// Full-screen pinch-to-zoom image preview, fetched through the pinned +
/// authenticated [AgentClient].
class ImagePreviewScreen extends StatefulWidget {
  const ImagePreviewScreen({
    super.key,
    required this.entry,
    required this.client,
    this.heroTag,
    this.chromeless = false,
  });

  final Entry entry;
  final AgentClient client;

  /// When set, the displayed image is wrapped in a [Hero] with this tag so it
  /// animates from the explorer thumbnail. Only meaningful for image entries.
  final Object? heroTag;

  /// When `true`, omit the app bar so a host ([PreviewPager]) can overlay one
  /// shared top bar across sibling pages.
  final bool chromeless;

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Uint8List> _load() async {
    final size = widget.entry.size;
    if (size != null && size > kMaxInMemoryPreviewBytes) {
      throw _TooLarge(size);
    }
    // Go through the shared preview cache so neighbours preloaded by the pager
    // are reused instantly instead of refetched.
    return PreviewImageCache.instance.fetch(widget.client, widget.entry.path);
  }

  void _retry() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return PreviewScaffold(
      title: widget.entry.name,
      backgroundColor: Colors.black,
      chromeless: widget.chromeless,
      body: FutureBuilder<Uint8List>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const PreviewLoading(message: 'Loading image…');
          }
          if (snapshot.hasError) {
            final err = snapshot.error;
            if (err is _TooLarge) {
              return PreviewTooLarge(sizeLabel: formatSize(err.size));
            }
            return PreviewError(
              message: 'Could not load image.\n$err',
              onRetry: _retry,
            );
          }
          final bytes = snapshot.data!;
          Widget photo = PhotoView(
            imageProvider: MemoryImage(bytes),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 4,
            loadingBuilder:
                (context, event) =>
                    const PreviewLoading(message: 'Decoding image…'),
            errorBuilder:
                (context, error, stackTrace) => PreviewError(
                  message: 'Could not decode this image.\n$error',
                ),
          );
          if (widget.heroTag != null) {
            // A cheap Hero (no shaders) — Skia handles the transform/opacity
            // flight fine. Wrap the whole zoomable surface so the tile's
            // thumbnail lands on the preview image.
            photo = Hero(tag: widget.heroTag!, child: photo);
          }
          return photo;
        },
      ),
    );
  }
}

class _TooLarge implements Exception {
  _TooLarge(this.size);
  final int size;
}
