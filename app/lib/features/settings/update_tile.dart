import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/agent_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/app_release.dart';
import '../../core/models/host.dart';
import '../../core/update/update_service.dart';

/// A Settings tile that checks the host for a newer APK and installs it,
/// with clear feedback at every stage. Hidden on non-Android platforms.
///
/// Flow: tap → check → (if newer) a progress dialog downloads the APK with a
/// live percentage, then hands it to Android's package installer via a native
/// FileProvider intent (MainActivity.installApk). The installer runs in the
/// system UI — including any "install unknown apps" permission prompt — so
/// completion is confirmed when the app resumes by re-reading the installed
/// build number.
class UpdateTile extends ConsumerStatefulWidget {
  const UpdateTile({super.key, required this.host});
  final Host host;

  @override
  ConsumerState<UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends ConsumerState<UpdateTile>
    with WidgetsBindingObserver {
  // Native channel into MainActivity (shared with the downloads helper).
  static const _platform = MethodChannel('rfe/downloads');

  String _status = '';
  bool _busy = false;
  bool _statusIsError = false;

  // Set when we hand an APK to the system installer; on the next app resume we
  // re-check the installed version to confirm whether the update completed.
  bool _installLaunched = false;
  int _preInstallBuild = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _installLaunched) {
      _installLaunched = false;
      _confirmInstallOnResume();
    }
  }

  Future<void> _confirmInstallOnResume() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final now = int.tryParse(info.buildNumber) ?? 0;
      if (!mounted) return;
      if (now > _preInstallBuild) {
        setState(() {
          _status = 'Updated to v${info.version} ✓';
          _statusIsError = false;
          _busy = false;
        });
      } else {
        setState(() {
          _status = 'Update not completed — tap to retry.';
          _statusIsError = true;
          _busy = false;
        });
      }
    } catch (_) {
      // Best effort; leave the prior status in place.
    }
  }

  Future<void> _checkAndInstall() async {
    if (!Platform.isAndroid) return;
    setState(() {
      _busy = true;
      _status = 'Checking for updates…';
      _statusIsError = false;
    });
    final client = await buildClientForHost(ref.read, widget.host.id);
    try {
      final AppRelease? rel = await client.latestRelease();
      final info = await PackageInfo.fromPlatform();
      final installed = int.tryParse(info.buildNumber) ?? 0;

      if (!isUpdateAvailable(installedBuild: installed, release: rel)) {
        setState(() {
          _busy = false;
          _status = 'Up to date (v${info.version})';
          _statusIsError = false;
        });
        return;
      }

      // Prepare the destination file in external cache (covered by the
      // FileProvider paths so the installer can read it).
      final dirs = await getExternalCacheDirectories();
      final base = (dirs != null && dirs.isNotEmpty)
          ? dirs.first
          : await getTemporaryDirectory();
      final apk = File('${base.path}/update-${rel!.versionCode}.apk');

      // Remove any previously downloaded APKs so updates don't pile up in the
      // app's cache — only the one we're about to install is kept.
      await _pruneOldApks(base, keep: apk);

      _preInstallBuild = installed;

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UpdateProgressDialog(
          client: client,
          release: rel,
          apk: apk,
          onLaunchInstaller: _launchInstaller,
        ),
      );

      if (!mounted) return;
      // If the installer was handed off, reflect that and let resume confirm it.
      if (_installLaunched) {
        setState(() {
          _busy = true;
          _status = 'Opening installer — confirm in Android, then return here.';
          _statusIsError = false;
        });
      } else {
        setState(() => _busy = false);
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _status = 'Update failed: $e';
        _statusIsError = true;
      });
    } finally {
      client.close();
    }
  }

  /// Deletes stale `update-*.apk` files in [dir], keeping only [keep]. Best
  /// effort: failures (e.g. a file held open) are ignored.
  Future<void> _pruneOldApks(Directory dir, {required File keep}) async {
    try {
      await for (final e in dir.list()) {
        if (e is File &&
            e.path != keep.path &&
            e.uri.pathSegments.last.startsWith('update-') &&
            e.path.endsWith('.apk')) {
          try {
            await e.delete();
          } catch (_) {/* ignore individual file errors */}
        }
      }
    } catch (_) {/* ignore: cleanup is best effort */}
  }

  /// Hands the APK to Android's package installer through the native channel.
  /// Records that an install was launched so the resume handler can confirm the
  /// outcome. Throws on failure (handled by the caller).
  Future<void> _launchInstaller(File apk) async {
    _installLaunched = true;
    await _platform.invokeMethod<void>('installApk', {'path': apk.path});
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !kIsWeb) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        _statusIsError ? Icons.error_outline : Icons.system_update,
        color: _statusIsError ? scheme.error : null,
      ),
      title: const Text('Check for updates'),
      subtitle: _status.isEmpty
          ? null
          : Text(
              _status,
              style: _statusIsError
                  ? TextStyle(color: scheme.error)
                  : null,
            ),
      trailing: _busy
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: _busy ? null : _checkAndInstall,
    );
  }
}

// ---------------------------------------------------------------------------
// Progress dialog
// ---------------------------------------------------------------------------

enum _Stage { downloading, opening, error, cancelled }

/// Modal dialog that downloads the APK (with a live percentage) and hands it to
/// the installer, surfacing a clear result for every outcome.
class _UpdateProgressDialog extends StatefulWidget {
  const _UpdateProgressDialog({
    required this.client,
    required this.release,
    required this.apk,
    required this.onLaunchInstaller,
  });

  final AgentClient client;
  final AppRelease release;
  final File apk;
  final Future<void> Function(File apk) onLaunchInstaller;

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  _Stage _stage = _Stage.downloading;
  double? _progress;
  int _received = 0;
  int _total = 0;
  String? _errorMsg;

  /// Cancels the in-flight APK download when the user taps Cancel. Replaced
  /// with a fresh token on each Retry so a cancelled token can't poison a
  /// later attempt.
  CancelToken _cancelToken = CancelToken();

  @override
  void initState() {
    super.initState();
    _download();
  }

  @override
  void dispose() {
    if (!_cancelToken.isCancelled) _cancelToken.cancel();
    super.dispose();
  }

  Future<void> _download() async {
    _cancelToken = CancelToken();
    setState(() {
      _stage = _Stage.downloading;
      _progress = null;
      _errorMsg = null;
    });
    try {
      // Resume from whatever is already on disk. The APK is named for this
      // release's versionCode and stale APKs were pruned before the dialog
      // opened, so any existing bytes belong to exactly this download.
      final startByte =
          await widget.apk.exists() ? await widget.apk.length() : 0;
      await widget.client.downloadApk(
        localFile: widget.apk,
        startByte: startByte,
        cancelToken: _cancelToken,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
            _progress = total > 0 ? received / total : null;
          });
        },
      );
      await _install();
    } on RangeNotSatisfiedException {
      // Server couldn't honor the resume (it deleted the corrupt partial);
      // restart cleanly from the beginning.
      if (mounted) await _download();
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.type == DioExceptionType.cancel) {
        // Partial bytes are kept on disk; Retry resumes from here.
        setState(() => _stage = _Stage.cancelled);
        return;
      }
      setState(() {
        _stage = _Stage.error;
        _errorMsg = '$e';
      });
    } on AgentApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMsg = e.message.isNotEmpty ? e.message : '$e';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMsg = '$e';
      });
    }
  }

  /// Aborts the in-flight download. The cancellation surfaces back to
  /// [_download]'s catch block, which moves to [_Stage.cancelled] — closing
  /// the dialog directly here would race with that and could pop twice.
  void _cancelDownload() {
    if (!_cancelToken.isCancelled) _cancelToken.cancel();
  }

  Future<void> _install() async {
    setState(() => _stage = _Stage.opening);
    try {
      await widget.onLaunchInstaller(widget.apk);
      if (!mounted) return;
      // Installer opened in the system UI — close; the tile confirms on resume.
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMsg = e is PlatformException
            ? (e.message ?? 'Could not open the installer.')
            : '$e';
      });
    }
  }

  String _fmtBytes(int b) {
    const mb = 1024 * 1024;
    if (b >= mb) return '${(b / mb).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '$b B';
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.release.versionName;
    return AlertDialog(
      title: Text('Updating to v$v'),
      content: _buildContent(context),
      actions: _buildActions(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (_stage) {
      case _Stage.downloading:
        final pct = _progress == null ? null : (_progress! * 100).round();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 12),
            Text(pct == null
                ? 'Downloading…'
                : 'Downloading $pct%  ·  ${_fmtBytes(_received)} / ${_fmtBytes(_total)}'),
          ],
        );
      case _Stage.opening:
        return const Row(
          children: [
            SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 16),
            Expanded(child: Text('Opening installer…')),
          ],
        );
      case _Stage.error:
        return Text(_errorMsg ?? 'Something went wrong.');
      case _Stage.cancelled:
        return const Text('Download paused. Retry to resume where it left off.');
    }
  }

  List<Widget> _buildActions(BuildContext context) {
    switch (_stage) {
      case _Stage.downloading:
        return [
          TextButton(
            onPressed: _cancelDownload,
            child: const Text('Cancel'),
          ),
        ];
      case _Stage.opening:
        // The APK is already fully downloaded and handed to the installer —
        // nothing left to cancel.
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ];
      case _Stage.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: _download,
            child: const Text('Retry'),
          ),
        ];
      case _Stage.cancelled:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: _download,
            child: const Text('Retry'),
          ),
        ];
    }
  }
}

/// Standalone screen hosting [UpdateTile], reachable from the host card menu
/// and the launch-time "Update available" banner.
class UpdateScreen extends StatelessWidget {
  const UpdateScreen({super.key, required this.host});
  final Host host;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(host.label)),
      body: ListView(
        children: [
          UpdateTile(host: host),
        ],
      ),
    );
  }
}
