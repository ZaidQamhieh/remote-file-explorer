import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/format.dart';
import 'preview_common.dart';

/// Audio preview: downloads the file to a temp cache file (showing progress),
/// then plays it through `video_player` (which decodes audio-only files just
/// as well as video) behind a compact custom transport — artwork glyph, file
/// name, a scrubbable position slider, elapsed/total times, and play/pause.
///
/// Same constraint as [VideoPreviewScreen]: we can't stream straight from the
/// agent because the player needs a local file or a plain network URL, and the
/// agent requires TLS pinning + bearer auth that a raw network URL can't carry.
/// So we reuse the proven download-to-temp path rather than add a second media
/// stack (`just_audio`) and its native surface.
class AudioPreviewScreen extends StatefulWidget {
  const AudioPreviewScreen({
    super.key,
    required this.entry,
    required this.client,
    this.chromeless = false,
  });

  final Entry entry;
  final AgentClient client;

  /// When `true`, omit the app bar so a host ([PreviewPager]) can overlay one
  /// shared top bar across sibling pages.
  final bool chromeless;

  @override
  State<AudioPreviewScreen> createState() => _AudioPreviewScreenState();
}

class _AudioPreviewScreenState extends State<AudioPreviewScreen> {
  late Future<VideoPlayerController> _future;
  VideoPlayerController? _player;
  File? _tempFile;

  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<VideoPlayerController> _load() async {
    final size = widget.entry.size;
    if (size != null && size > kMaxAudioPreviewBytes) {
      throw _TooLarge(size);
    }

    final dir = await getTemporaryDirectory();
    final previewDir = Directory('${dir.path}/preview_cache');
    if (!await previewDir.exists()) {
      await previewDir.create(recursive: true);
    }
    final safeName = widget.entry.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final file = File('${previewDir.path}/$safeName');
    _tempFile = file;

    if (await file.exists()) {
      await file.delete();
    }

    await widget.client.downloadFile(
      remotePath: widget.entry.path,
      localFile: file,
      onProgress: (received, total) {
        if (!mounted) return;
        if (total > 0) {
          setState(() => _progress = received / total);
        }
      },
    );

    final player = VideoPlayerController.file(file);
    _player = player;
    await player.initialize();
    // Rebuild on position/state changes so the slider + times track playback.
    player.addListener(_onPlayerTick);
    await player.play();
    return player;
  }

  void _onPlayerTick() {
    if (mounted) setState(() {});
  }

  void _retry() {
    setState(() {
      _progress = 0;
      _disposePlayer();
      _future = _load();
    });
  }

  void _disposePlayer() {
    _player?.removeListener(_onPlayerTick);
    _player?.dispose();
    _player = null;
  }

  @override
  void dispose() {
    _disposePlayer();
    _tempFile?.delete().catchError((_) => _tempFile!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PreviewScaffold(
      title: widget.entry.name,
      chromeless: widget.chromeless,
      body: FutureBuilder<VideoPlayerController>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return PreviewLoading(
              message:
                  'Downloading audio for preview… '
                  '${(_progress * 100).toStringAsFixed(0)}%',
              progress: _progress > 0 ? _progress : null,
            );
          }
          if (snapshot.hasError) {
            final err = snapshot.error;
            if (err is _TooLarge) {
              return PreviewTooLarge(sizeLabel: formatSize(err.size));
            }
            return PreviewError(
              message: 'Could not load this audio.\n$err',
              onRetry: _retry,
            );
          }
          return _AudioTransport(
            controller: snapshot.data!,
            title: widget.entry.name,
          );
        },
      ),
    );
  }
}

/// The audio playback UI: artwork glyph, file name, scrub slider, elapsed /
/// total time labels, and a play/pause (or replay-at-end) control.
class _AudioTransport extends StatelessWidget {
  const _AudioTransport({required this.controller, required this.title});

  final VideoPlayerController controller;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = controller.value;
    final duration = value.duration;
    final position = value.position > duration ? duration : value.position;
    final ended = duration > Duration.zero && position >= duration;
    final maxMs = duration.inMilliseconds.toDouble();
    final posMs = position.inMilliseconds.toDouble().clamp(0, maxMs);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.music_note, size: 96, color: scheme.primary),
            const SizedBox(height: Spacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: Spacing.lg),
            Slider(
              value: posMs.toDouble(),
              max: maxMs <= 0 ? 1 : maxMs,
              onChanged:
                  maxMs <= 0
                      ? null
                      : (v) =>
                          controller.seekTo(Duration(milliseconds: v.round())),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatDuration(position),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    formatDuration(duration),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.md),
            Center(
              child: IconButton.filled(
                iconSize: 48,
                icon: Icon(
                  ended
                      ? Icons.replay
                      : (value.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                onPressed: () {
                  if (ended) {
                    controller.seekTo(Duration.zero);
                    controller.play();
                  } else if (value.isPlaying) {
                    controller.pause();
                  } else {
                    controller.play();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TooLarge implements Exception {
  _TooLarge(this.size);
  final int size;
}
