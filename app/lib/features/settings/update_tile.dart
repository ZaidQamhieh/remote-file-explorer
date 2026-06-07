import 'dart:io';

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

/// A Settings tile that checks the host for a newer APK and installs it.
/// Hidden on non-Android platforms.
class UpdateTile extends ConsumerStatefulWidget {
  const UpdateTile({super.key, required this.host});
  final Host host;

  @override
  ConsumerState<UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends ConsumerState<UpdateTile> {
  String _status = '';
  bool _busy = false;
  double? _progress;

  Future<void> _checkAndInstall() async {
    if (!Platform.isAndroid) return;
    setState(() {
      _busy = true;
      _status = 'Checking…';
      _progress = null;
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
        });
        return;
      }

      setState(() => _status = 'Downloading v${rel!.versionName}…');
      final dir = await getExternalCacheDirectories();
      final base = (dir != null && dir.isNotEmpty)
          ? dir.first
          : await getTemporaryDirectory();
      final file = File('${base.path}/update-${rel!.versionCode}.apk');
      await client.downloadApk(
        localFile: file,
        onProgress: (r, t) {
          if (t > 0) setState(() => _progress = r / t);
        },
      );

      setState(() => _status = 'Launching installer…');
      await _installApk(file.path, info.packageName);
      setState(() {
        _busy = false;
        _status = 'Installer launched — confirm to update.';
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _status = 'Update failed: $e';
      });
    }
  }

  // Single point of plugin integration (chosen dependency: open_filex).
  // Opening the .apk routes Android to its package installer.
  Future<void> _installApk(String path, String appId) async {
    await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !kIsWeb) {
      // Updater is Android-only; render nothing elsewhere.
      return const SizedBox.shrink();
    }
    return ListTile(
      leading: const Icon(Icons.system_update),
      title: const Text('Check for updates'),
      subtitle: _status.isEmpty ? null : Text(_status),
      trailing: _busy
          ? SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2, value: _progress),
            )
          : const Icon(Icons.chevron_right),
      onTap: _busy ? null : _checkAndInstall,
    );
  }
}

/// Standalone screen hosting [UpdateTile].
///
/// Pillar A introduces a full Settings screen; until that is merged, the
/// in-app updater is reachable through this minimal screen (from the host
/// card menu and the launch-time "Update available" banner).
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
