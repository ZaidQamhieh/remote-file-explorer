import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Maximum size (in bytes) we'll happily load fully into memory for an
/// in-app preview (images, text, PDFs). Beyond this we show a
/// "too large to preview" state and suggest downloading instead.
const int kMaxInMemoryPreviewBytes = 50 * 1024 * 1024; // 50 MB

/// Maximum size (in bytes) we'll download to a temp cache file for video
/// preview playback. Beyond this we suggest downloading via the transfer
/// queue instead of streaming a full local copy just to preview it.
const int kMaxVideoPreviewBytes = 300 * 1024 * 1024; // 300 MB

/// A simple `Scaffold` shell shared by all preview viewers: an `AppBar`
/// with the file name, and a body that reflects [PreviewLoadState].
class PreviewScaffold extends StatelessWidget {
  const PreviewScaffold({
    super.key,
    required this.title,
    required this.body,
    this.backgroundColor,
    this.actions,
  });

  final String title;
  final Widget body;
  final Color? backgroundColor;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    // Image/video previews sit on a black canvas — render the chrome as a
    // translucent overlay with light foreground so it reads on dark media
    // without fighting the surrounding theme.
    final onDark = backgroundColor == Colors.black;
    final appBar = onDark
        ? AppBar(
            backgroundColor: Colors.black.withValues(alpha: 0.45),
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(title, overflow: TextOverflow.ellipsis),
            actions: actions,
          )
        : AppBar(
            title: Text(title, overflow: TextOverflow.ellipsis),
            actions: actions,
          );

    return Scaffold(
      backgroundColor: backgroundColor,
      extendBodyBehindAppBar: onDark,
      appBar: appBar,
      body: body,
    );
  }
}

/// Centered loading indicator with an optional status message — used while
/// preview content is being fetched/decoded.
class PreviewLoading extends StatelessWidget {
  const PreviewLoading({super.key, this.message, this.progress});

  final String? message;

  /// Optional 0.0–1.0 progress value (e.g. download progress for video).
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(value: progress),
          if (message != null) ...[
            const SizedBox(height: Spacing.md),
            Text(message!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// Centered error state with an icon and message — used when fetching or
/// decoding preview content fails.
class PreviewError extends StatelessWidget {
  const PreviewError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: Spacing.md),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: Spacing.md),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Centered "file too large to preview" state, suggesting a download.
class PreviewTooLarge extends StatelessWidget {
  const PreviewTooLarge({super.key, required this.sizeLabel});

  final String sizeLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.file_present,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: Spacing.md),
            Text(
              'This file is too large to preview ($sizeLabel).\n'
              'Download it to view it instead.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Human-readable byte size, matching the formatting used elsewhere in the
/// app (see `meta_sheet.dart`).
String formatBytes(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
