import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/agent_client.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/entry.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/format.dart';
import 'preview_common.dart';

/// Audio preview: downloads the file to a temp cache file (showing progress),
/// then plays it through `just_audio` behind a compact custom transport —
/// artwork glyph, file name, a scrubbable position slider, elapsed/total times,
/// playback speed selector, and play/pause.
///
/// Same constraint as [VideoPreviewScreen]: we can't stream straight from the
/// agent because the player needs a local file or a plain network URL, and the
/// agent requires TLS pinning + bearer auth that a raw network URL can't carry.
/// So we reuse the proven download-to-temp path.
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
  late Future<AudioPlayer> _future;
  AudioPlayer? _player;
  File? _tempFile;

  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<AudioPlayer> _load() async {
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

    final player = AudioPlayer();
    _player = player;
    await player.setFilePath(file.path);
    player.play();
    return player;
  }

  void _retry() {
    setState(() {
      _progress = 0;
      _disposePlayer();
      _future = _load();
    });
  }

  void _disposePlayer() {
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
      body: FutureBuilder<AudioPlayer>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return PreviewLoading(
              message: context.l10n.audioDownloadingProgress(
                (_progress * 100).toStringAsFixed(0),
              ),
              progress: _progress > 0 ? _progress : null,
            );
          }
          if (snapshot.hasError) {
            final err = snapshot.error;
            if (err is _TooLarge) {
              return PreviewTooLarge(sizeLabel: formatSize(err.size));
            }
            return PreviewError(
              message: context.l10n.couldNotLoadAudio(err.toString()),
              onRetry: _retry,
            );
          }
          return _AudioTransport(
            player: snapshot.data!,
            title: widget.entry.name,
          );
        },
      ),
    );
  }
}

/// Available playback speed presets.
const _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// The audio playback UI: artwork glyph, file name, scrub slider, elapsed /
/// total time labels, speed selector, and a play/pause (or replay) control.
class _AudioTransport extends StatelessWidget {
  const _AudioTransport({required this.player, required this.title});

  final AudioPlayer player;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
            _SeekBar(player: player),
            const SizedBox(height: Spacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SpeedButton(player: player),
                const SizedBox(width: Spacing.lg),
                _PlayPauseButton(player: player),
                const SizedBox(width: Spacing.lg),
                // Spacer to balance the speed button visually.
                const SizedBox(width: 48),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Scrub slider with elapsed / remaining time labels, rebuilt via streams.
class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.player});

  final AudioPlayer player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, posSnap) {
        final duration = player.duration ?? Duration.zero;
        final position = posSnap.data ?? Duration.zero;
        final clamped = position > duration ? duration : position;
        final maxMs = duration.inMilliseconds.toDouble();
        final posMs = clamped.inMilliseconds.toDouble().clamp(0.0, maxMs);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Slider(
              value: posMs,
              max: maxMs <= 0 ? 1 : maxMs,
              onChanged:
                  maxMs <= 0
                      ? null
                      : (v) => player.seek(Duration(milliseconds: v.round())),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatDuration(clamped),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    formatDuration(duration),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Play / pause / replay button rebuilt from the player state stream.
class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.player});

  final AudioPlayer player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final processing = state?.processingState ?? ProcessingState.idle;
        final playing = state?.playing ?? false;
        final completed = processing == ProcessingState.completed;

        return IconButton.filled(
          iconSize: 48,
          icon: Icon(
            completed
                ? Icons.replay
                : (playing ? Icons.pause : Icons.play_arrow),
          ),
          onPressed: () {
            if (completed) {
              player.seek(Duration.zero);
              player.play();
            } else if (playing) {
              player.pause();
            } else {
              player.play();
            }
          },
        );
      },
    );
  }
}

/// Playback speed selector button — shows the current speed and opens a menu
/// with preset options.
class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.player});

  final AudioPlayer player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: player.speedStream,
      builder: (context, snapshot) {
        final speed = snapshot.data ?? 1.0;
        return PopupMenuButton<double>(
          tooltip: context.l10n.audioSpeedLabel,
          onSelected: player.setSpeed,
          itemBuilder:
              (_) => [
                for (final s in _speedOptions)
                  PopupMenuItem(
                    value: s,
                    child: Text(
                      context.l10n.audioSpeedValue(
                        s == s.roundToDouble()
                            ? s.toStringAsFixed(0)
                            : s.toString(),
                      ),
                      style: TextStyle(
                        fontWeight: s == speed ? FontWeight.bold : null,
                      ),
                    ),
                  ),
              ],
          child: Padding(
            padding: const EdgeInsets.all(Spacing.sm),
            child: Text(
              context.l10n.audioSpeedValue(
                speed == speed.roundToDouble()
                    ? speed.toStringAsFixed(0)
                    : speed.toString(),
              ),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        );
      },
    );
  }
}

class _TooLarge implements Exception {
  _TooLarge(this.size);
  final int size;
}
