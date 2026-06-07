import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import 'preview_common.dart';

/// Full-screen pinch-to-zoom image preview, fetched through the pinned +
/// authenticated [AgentClient].
class ImagePreviewScreen extends StatefulWidget {
  const ImagePreviewScreen({
    super.key,
    required this.entry,
    required this.client,
  });

  final Entry entry;
  final AgentClient client;

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
    return widget.client.fetchBytes(widget.entry.path);
  }

  void _retry() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return PreviewScaffold(
      title: widget.entry.name,
      backgroundColor: Colors.black,
      body: FutureBuilder<Uint8List>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const PreviewLoading(message: 'Loading image…');
          }
          if (snapshot.hasError) {
            final err = snapshot.error;
            if (err is _TooLarge) {
              return PreviewTooLarge(sizeLabel: formatBytes(err.size));
            }
            return PreviewError(
              message: 'Could not load image.\n$err',
              onRetry: _retry,
            );
          }
          final bytes = snapshot.data!;
          return PhotoView(
            imageProvider: MemoryImage(bytes),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 4,
            loadingBuilder: (context, event) =>
                const PreviewLoading(message: 'Decoding image…'),
            errorBuilder: (context, error, stackTrace) => PreviewError(
              message: 'Could not decode this image.\n$error',
            ),
          );
        },
      ),
    );
  }
}

class _TooLarge implements Exception {
  _TooLarge(this.size);
  final int size;
}
