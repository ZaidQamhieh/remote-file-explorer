import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/ui/format.dart';
import 'preview_common.dart';

/// SharedPreferences key where we persist `{filePath: positionMs}` pairs
/// so users can resume playback where they left off.
const String kVideoPositionsKey = 'rfe_video_positions';

/// Seek delta applied on double-tap (seconds).
const int _kSeekDeltaSeconds = 10;

/// Video preview: downloads the file to a temp cache file (showing progress),
/// then hands the local path to `video_player`/`chewie` for playback with
/// standard controls.
///
/// We can't stream straight from the agent because `video_player` needs a
/// local file or a plain network URL — and the agent requires TLS pinning +
/// bearer auth that a raw `VideoPlayerController.networkUrl` can't provide.
class VideoPreviewScreen extends StatefulWidget {
  const VideoPreviewScreen({
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
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  late Future<ChewieController> _future;
  ChewieController? _chewie;
  VideoPlayerController? _video;
  File? _tempFile;

  double _progress = 0;

  /// Which side showed the seek indicator last (null = hidden).
  _SeekSide? _seekSide;
  Timer? _seekOverlayTimer;

  /// Whether the video completed (position >= duration). Used to clear the
  /// saved resume position so completed videos restart from the beginning.
  bool _completedNaturally = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ChewieController> _load() async {
    // Capture theme-derived values before any `await` — `context` shouldn't
    // be used across async gaps.
    final primaryColor = Theme.of(context).colorScheme.primary;

    final size = widget.entry.size;
    if (size != null && size > kMaxVideoPreviewBytes) {
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

    final video = VideoPlayerController.file(file);
    _video = video;
    await video.initialize();

    final chewie = ChewieController(
      videoPlayerController: video,
      autoPlay: false, // we'll play after seeking to resume position
      looping: false,
      allowFullScreen: true,
      allowMuting: true,
      materialProgressColors: ChewieProgressColors(
        playedColor: primaryColor,
        handleColor: primaryColor,
      ),
    );
    _chewie = chewie;

    // Resume from saved position, then start playback.
    await _maybeResumePosition(video);
    await video.play();

    // Listen for completion to clear saved position.
    video.addListener(_onVideoPositionChanged);

    return chewie;
  }

  /// If a position was previously saved for this file, seek to it and show a
  /// snackbar. We clear the saved position immediately — it'll be re-saved
  /// on dispose if the user pauses or leaves mid-video.
  Future<void> _maybeResumePosition(VideoPlayerController video) async {
    final prefs = await SharedPreferences.getInstance();
    final posMs = _readPosition(prefs, widget.entry.path);
    if (posMs == null || posMs <= 0) return;

    final duration = video.value.duration;
    final resumePos = Duration(milliseconds: posMs);

    // Don't resume if position is at or past the end.
    if (duration > Duration.zero && resumePos >= duration) return;

    await video.seekTo(resumePos);

    if (mounted) {
      final label = formatDuration(resumePos);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Resuming from $label'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onVideoPositionChanged() {
    final video = _video;
    if (video == null) return;
    final value = video.value;
    if (!value.isInitialized) return;

    // Detect natural completion: position reached the end.
    if (value.duration > Duration.zero &&
        value.position >= value.duration - const Duration(milliseconds: 500)) {
      _completedNaturally = true;
    }
  }

  /// Seek forward or backward by [_kSeekDeltaSeconds].
  void _onDoubleTapSeek(_SeekSide side) {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;

    final current = video.value.position;
    final duration = video.value.duration;
    final delta = Duration(seconds: _kSeekDeltaSeconds);

    Duration target;
    if (side == _SeekSide.left) {
      target = current - delta;
      if (target < Duration.zero) target = Duration.zero;
    } else {
      target = current + delta;
      if (target > duration) target = duration;
    }

    video.seekTo(target);
    _showSeekOverlay(side);
  }

  void _showSeekOverlay(_SeekSide side) {
    _seekOverlayTimer?.cancel();
    setState(() => _seekSide = side);
    _seekOverlayTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _seekSide = null);
    });
  }

  void _retry() {
    setState(() {
      _progress = 0;
      _disposeControllers();
      _future = _load();
    });
  }

  void _disposeControllers() {
    _seekOverlayTimer?.cancel();
    _seekOverlayTimer = null;
    _video?.removeListener(_onVideoPositionChanged);
    _chewie?.dispose();
    _chewie = null;
    _video?.dispose();
    _video = null;
  }

  @override
  void dispose() {
    _savePosition();
    _disposeControllers();
    _tempFile?.delete().catchError((_) => _tempFile!);
    super.dispose();
  }

  /// Persist the current playback position so we can resume later.
  /// If the video completed naturally, clear the saved position instead.
  void _savePosition() {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;

    // Fire-and-forget — dispose can't await.
    SharedPreferences.getInstance().then((prefs) {
      if (_completedNaturally) {
        _clearPosition(prefs, widget.entry.path);
      } else {
        final posMs = video.value.position.inMilliseconds;
        if (posMs > 0) {
          _writePosition(prefs, widget.entry.path, posMs);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PreviewScaffold(
      title: widget.entry.name,
      backgroundColor: Colors.black,
      chromeless: widget.chromeless,
      body: FutureBuilder<ChewieController>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return PreviewLoading(
              message:
                  'Downloading video for preview… '
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
              message: 'Could not load this video.\n$err',
              onRetry: _retry,
            );
          }
          return _PlayerWithSeekOverlay(
            chewie: snapshot.data!,
            seekSide: _seekSide,
            onDoubleTap: _onDoubleTapSeek,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Seek overlay
// ---------------------------------------------------------------------------

enum _SeekSide { left, right }

/// Wraps [Chewie] in a [Stack] with transparent left/right double-tap zones
/// and an animated seek indicator.
class _PlayerWithSeekOverlay extends StatelessWidget {
  const _PlayerWithSeekOverlay({
    required this.chewie,
    required this.seekSide,
    required this.onDoubleTap,
  });

  final ChewieController chewie;
  final _SeekSide? seekSide;
  final ValueChanged<_SeekSide> onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: chewie.videoPlayerController.value.aspectRatio,
        child: Stack(
          children: [
            Chewie(controller: chewie),
            // Left half — double-tap to seek backward.
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1.0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: () => onDoubleTap(_SeekSide.left),
                  ),
                ),
              ),
            ),
            // Right half — double-tap to seek forward.
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1.0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: () => onDoubleTap(_SeekSide.right),
                  ),
                ),
              ),
            ),
            // Seek indicator overlay.
            if (seekSide != null)
              Positioned.fill(child: _SeekIndicator(side: seekSide!)),
          ],
        ),
      ),
    );
  }
}

/// Animated "◄◄ 10s" / "10s ►►" indicator shown briefly after a double-tap
/// seek.
class _SeekIndicator extends StatefulWidget {
  const _SeekIndicator({required this.side});
  final _SeekSide side;

  @override
  State<_SeekIndicator> createState() => _SeekIndicatorState();
}

class _SeekIndicatorState extends State<_SeekIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 40),
    ]).animate(_anim);
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLeft = widget.side == _SeekSide.left;
    final label =
        isLeft ? '◄◄ ${_kSeekDeltaSeconds}s' : '${_kSeekDeltaSeconds}s ►►';

    return Align(
      alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: FadeTransition(
        opacity: _opacity,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Resume-position persistence helpers
// ---------------------------------------------------------------------------

/// Read the saved position (in milliseconds) for [filePath], or null.
int? _readPosition(SharedPreferences prefs, String filePath) {
  // We store positions individually so we don't need to parse a JSON blob.
  return prefs.getInt('${kVideoPositionsKey}_$filePath');
}

/// Write the playback position for [filePath].
void _writePosition(SharedPreferences prefs, String filePath, int posMs) {
  prefs.setInt('${kVideoPositionsKey}_$filePath', posMs);
}

/// Clear the saved position for [filePath] (video completed).
void _clearPosition(SharedPreferences prefs, String filePath) {
  prefs.remove('${kVideoPositionsKey}_$filePath');
}

class _TooLarge implements Exception {
  _TooLarge(this.size);
  final int size;
}
