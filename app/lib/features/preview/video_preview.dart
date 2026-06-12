import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/ui/format.dart';
import 'preview_common.dart';

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
  });

  final Entry entry;
  final AgentClient client;

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  late Future<ChewieController> _future;
  ChewieController? _chewie;
  VideoPlayerController? _video;
  File? _tempFile;

  double _progress = 0;

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
      autoPlay: true,
      looping: false,
      allowFullScreen: true,
      allowMuting: true,
      materialProgressColors: ChewieProgressColors(
        playedColor: primaryColor,
        handleColor: primaryColor,
      ),
    );
    _chewie = chewie;
    return chewie;
  }

  void _retry() {
    setState(() {
      _progress = 0;
      _disposeControllers();
      _future = _load();
    });
  }

  void _disposeControllers() {
    _chewie?.dispose();
    _chewie = null;
    _video?.dispose();
    _video = null;
  }

  @override
  void dispose() {
    _disposeControllers();
    _tempFile?.delete().catchError((_) => _tempFile!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PreviewScaffold(
      title: widget.entry.name,
      backgroundColor: Colors.black,
      body: FutureBuilder<ChewieController>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return PreviewLoading(
              message: 'Downloading video for preview… '
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
          return Center(
            child: AspectRatio(
              aspectRatio: snapshot.data!.videoPlayerController.value.aspectRatio,
              child: Chewie(controller: snapshot.data!),
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
