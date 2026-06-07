import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/app_release.dart';
import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
import '../../core/update/update_service.dart';

/// A Settings tile that checks the host for a newer APK and installs it,
/// with clear feedback at every stage. Hidden on non-Android platforms.
///
/// Flow: tap → check → (if newer) a progress dialog downloads the APK with a
/// live percentage, then hands it to Android's package installer. The installer
/// runs in the system UI, so completion is confirmed when the app resumes by
/// re-reading the installed build number.
class UpdateTile extends ConsumerStatefulWidget {
  const UpdateTile({super.key, required this.host});
  final Host host;

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
    try {
      final store = await ref.read(hostStoreProvider.future);
      final token = await store.getToken(widget.host.id);
      final client = AgentClient(widget.host, deviceToken: token);

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
          onOpenPermissionSettings: () =>
              _openUnknownSourcesSettings(info.packageName),
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
    }
  }

  /// Hands the APK to Android's package installer. Records that an install was
  /// launched so the resume handler can confirm the outcome.
  Future<OpenResult> _launchInstaller(File apk) async {
    _installLaunched = true;
    return OpenFilex.open(
      apk.path,
      type: 'application/vnd.android.package-archive',
    );
  }

  /// Opens the per-app "Install unknown apps" settings page so the user can
  /// grant permission, then return and retry.
  Future<void> _openUnknownSourcesSettings(String appId) async {
    final intent = AndroidIntent(
      action: 'android.settings.MANAGE_UNKNOWN_APP_SOURCES',
      data: 'package:$appId',
    );
    await intent.launch();
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

enum _Stage { downloading, opening, permissionDenied, error }

/// Modal dialog that downloads the APK (with a live percentage) and hands it to
/// the installer, surfacing a clear result for every outcome.
class _UpdateProgressDialog extends StatefulWidget {
  const _UpdateProgressDialog({
    required this.client,
    required this.release,
    required this.apk,
    required this.onLaunchInstaller,
    required this.onOpenPermissionSettings,
  });

  final AgentClient client;
  final AppRelease release;
  final File apk;
  final Future<OpenResult> Function(File apk) onLaunchInstaller;
  final Future<void> Function() onOpenPermissionSettings;

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

  Future<void> _download() async {
    setState(() {
      _stage = _Stage.downloading;
      _progress = null;
      _errorMsg = null;
    });
    try {
      await widget.client.downloadApk(
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMsg = '$e';
      });
    }
  }

  Future<void> _install() async {
    setState(() => _stage = _Stage.opening);
    final result = await widget.onLaunchInstaller(widget.apk);
    if (!mounted) return;
    switch (result.type) {
      case ResultType.done:
        // Installer opened in the system UI — close; the tile confirms on resume.
        Navigator.of(context).pop();
      case ResultType.permissionDenied:
        setState(() => _stage = _Stage.permissionDenied);
      case ResultType.noAppToOpen:
      case ResultType.fileNotFound:
      case ResultType.error:
        setState(() {
          _stage = _Stage.error;
          _errorMsg = result.message.isEmpty
              ? 'Could not open the installer.'
              : result.message;
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
      title: Text(_stage == _Stage.permissionDenied
          ? 'Permission needed'
          : 'Updating to v$v'),
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
      case _Stage.permissionDenied:
        return const Text(
          'Android needs permission to let this app install updates. '
          'Open settings, enable "Allow from this source", then come back '
          'and tap Retry.',
        );
      case _Stage.error:
        return Text(_errorMsg ?? 'Something went wrong.');
    }
  }

  List<Widget> _buildActions(BuildContext context) {
    switch (_stage) {
      case _Stage.downloading:
      case _Stage.opening:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ];
      case _Stage.permissionDenied:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              await widget.onOpenPermissionSettings();
            },
            child: const Text('Open settings'),
          ),
          FilledButton(
            onPressed: _install,
            child: const Text('Retry'),
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
