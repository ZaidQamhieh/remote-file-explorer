import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/api/agent_client.dart' show RangeNotSatisfiedException;
import '../../core/l10n_ext.dart';
import '../../core/models/app_release.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/update/auto_update.dart';
import '../../core/update/github_update_source.dart';
import '../../core/update/update_service.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// Native channel into MainActivity (shared with the downloads helper).
const _kInstallChannel = MethodChannel('rfe/downloads');

/// Hands [apk] to Android's package installer through the native channel.
/// Throws on failure (handled by the caller).
Future<void> launchInstaller(File apk) async {
  await _kInstallChannel.invokeMethod<void>('installApk', {'path': apk.path});
}

/// Deletes stale `update-*.apk` files in [dir], keeping only [keep]. Best
/// effort: failures (e.g. a file held open) are ignored.
Future<void> pruneOldApks(Directory dir, {required File keep}) async {
  try {
    await for (final e in dir.list()) {
      if (e is File &&
          e.path != keep.path &&
          e.uri.pathSegments.last.startsWith('update-') &&
          e.path.endsWith('.apk')) {
        try {
          await e.delete();
        } catch (_) {
          /* ignore individual file errors */
        }
      }
    }
  } catch (_) {
    /* ignore: cleanup is best effort */
  }
}

/// Downloads (joining any in-flight pre-download) or, if already cached,
/// skips straight to installing [release] — showing the same progress
/// dialog [UpdateTile] uses. Shared so the "Update" banner can trigger
/// install directly instead of navigating to Settings → About & Support →
/// tapping the update tile again. [onLaunchInstaller] defaults to handing
/// the APK straight to the installer; [UpdateTile] passes its own wrapper
/// to track "install launched" state for its resume-confirmation UI.
Future<void> triggerUpdateInstall(
  BuildContext context,
  AppRelease release, {
  Future<void> Function(File apk)? onLaunchInstaller,
}) async {
  final install = onLaunchInstaller ?? launchInstaller;
  final apk = await apkCacheFileFor(release.versionCode);
  await pruneOldApks(apk.parent, keep: apk);

  if (await isApkReadyToInstall(release)) {
    await install(apk);
    return;
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder:
        (_) => _UpdateProgressDialog(
          source: GithubUpdateSource(),
          release: release,
          apk: apk,
          onLaunchInstaller: install,
        ),
  );
}

/// A Settings tile that checks GitHub Releases for a newer APK and installs
/// it, with clear feedback at every stage. Hidden on non-Android platforms.
///
/// This is app-wide and host-independent — it lives once in App Settings,
/// not per paired device.
///
/// Flow: tap → check → (if newer) a progress dialog downloads the APK with a
/// live percentage, then hands it to Android's package installer via a native
/// FileProvider intent (MainActivity.installApk). The installer runs in the
/// system UI — including any "install unknown apps" permission prompt — so
/// completion is confirmed when the app resumes by re-reading the installed
/// build number.
class UpdateTile extends ConsumerStatefulWidget {
  const UpdateTile({super.key});

  @override
  ConsumerState<UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends ConsumerState<UpdateTile>
    with WidgetsBindingObserver {
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
          _status = context.l10n.updatedToVersion(info.version);
          _statusIsError = false;
          _busy = false;
        });
      } else {
        setState(() {
          _status = context.l10n.updateNotCompleted;
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
      _status = context.l10n.checkingForUpdates;
      _statusIsError = false;
    });
    final source = GithubUpdateSource();
    try {
      final AppRelease? rel = await source.latestRelease();
      final info = await PackageInfo.fromPlatform();
      final installed = int.tryParse(info.buildNumber) ?? 0;

      if (!isUpdateAvailable(installedBuild: installed, release: rel)) {
        setState(() {
          _busy = false;
          _status = context.l10n.upToDate(info.version);
          _statusIsError = false;
        });
        return;
      }

      _preInstallBuild = installed;
      if (!mounted) return;
      await triggerUpdateInstall(
        context,
        rel!,
        onLaunchInstaller: _launchInstaller,
      );
      if (!mounted) return;
      // If the installer was handed off, reflect that and let resume confirm it.
      setState(() {
        _busy = _installLaunched;
        if (_installLaunched) {
          _status = context.l10n.openingInstallerConfirm;
          _statusIsError = false;
        }
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _status = context.l10n.updateFailed('$e');
        _statusIsError = true;
      });
    }
  }

  /// Hands the APK to Android's package installer through the native channel.
  /// Records that an install was launched so the resume handler can confirm the
  /// outcome. Throws on failure (handled by the caller).
  Future<void> _launchInstaller(File apk) async {
    _installLaunched = true;
    await launchInstaller(apk);
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !kIsWeb) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        _statusIsError ? LucideIcons.circleAlert : LucideIcons.downloadCloud,
        color: _statusIsError ? scheme.error : null,
      ),
      title: Text(context.l10n.checkForUpdates),
      subtitle:
          _status.isEmpty
              ? null
              : Text(
                _status,
                style: _statusIsError ? TextStyle(color: scheme.error) : null,
              ),
      trailing:
          _busy
              ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(LucideIcons.chevronRight),
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
    required this.source,
    required this.release,
    required this.apk,
    required this.onLaunchInstaller,
  });

  final GithubUpdateSource source;
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

  @override
  void initState() {
    super.initState();
    _download();
  }

  @override
  void dispose() {
    cancelApkDownload(widget.release.versionCode);
    super.dispose();
  }

  Future<void> _download() async {
    setState(() {
      _stage = _Stage.downloading;
      _progress = null;
      _errorMsg = null;
    });
    try {
      // Joins the silent background pre-download if one is already in
      // flight for this release, instead of writing to the same cached
      // file concurrently (which corrupts it).
      await sharedDownloadApk(
        source: widget.source,
        release: widget.release,
        localFile: widget.apk,
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
        _errorMsg = humanizeError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMsg = humanizeError(e);
      });
    }
  }

  /// Aborts the in-flight download. The cancellation surfaces back to
  /// [_download]'s catch block, which moves to [_Stage.cancelled] — closing
  /// the dialog directly here would race with that and could pop twice.
  void _cancelDownload() {
    cancelApkDownload(widget.release.versionCode);
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
        _errorMsg =
            e is PlatformException
                ? (e.message ?? context.l10n.couldNotOpenInstaller)
                : '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.release.versionName;
    return AlertDialog(
      title: Text(context.l10n.updatingToVersion(v)),
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
            Text(
              pct == null
                  ? context.l10n.downloadingStatus
                  : context.l10n.downloadingProgress(
                    '$pct',
                    formatSize(_received),
                    formatSize(_total),
                  ),
            ),
          ],
        );
      case _Stage.opening:
        return Row(
          children: [
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(context.l10n.openingInstaller)),
          ],
        );
      case _Stage.error:
        return Text(_errorMsg ?? context.l10n.somethingWentWrong);
      case _Stage.cancelled:
        return Text(context.l10n.downloadPaused);
    }
  }

  List<Widget> _buildActions(BuildContext context) {
    switch (_stage) {
      case _Stage.downloading:
        return [
          TextButton(
            onPressed: _cancelDownload,
            child: Text(context.l10n.cancelButton),
          ),
        ];
      case _Stage.opening:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancelButton),
          ),
        ];
      case _Stage.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.closeButton),
          ),
          FilledButton(
            onPressed: _download,
            child: Text(context.l10n.retryButton),
          ),
        ];
      case _Stage.cancelled:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.closeButton),
          ),
          FilledButton(
            onPressed: _download,
            child: Text(context.l10n.retryButton),
          ),
        ];
    }
  }
}
