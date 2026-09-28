import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/providers.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/agent_settings.dart';
import '../../core/models/health.dart';
import '../../core/models/host.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/grouped_card.dart';
import '../../core/ui/screen_header.dart';
import '../../core/ui/state_views.dart';
import 'explorer_state.dart' show folderLabel;
import 'drives_view.dart';

typedef HostRootSelection = void Function(String rootPath, String? initialPath);

/// Effective settings are intentionally read from the agent: regular paired
/// devices receive only their effective folder jail, not the host-wide policy.
final hostBrowsingSettingsProvider = FutureProvider.autoDispose
    .family<AgentSettings, String>((ref, hostId) async {
      final client = await ref.watch(clientProvider(hostId).future);
      return client.getSettings();
    });

/// Selects a safe starting root for [path]. If roots overlap, the most
/// specific matching root wins so navigation cannot escape a nested jail.
String? allowedRootForPath(
  List<String> roots,
  String path, {
  bool windows = false,
}) {
  String normalize(String value) {
    var result = value.replaceAll('\\', '/');
    while (result.length > 1 &&
        result.endsWith('/') &&
        !RegExp(r'^[A-Za-z]:/$').hasMatch(result)) {
      result = result.substring(0, result.length - 1);
    }
    return windows ? result.toLowerCase() : result;
  }

  final candidate = normalize(path);
  String? best;
  var bestLength = -1;
  for (final root in roots) {
    final normalizedRoot = normalize(root);
    final prefix =
        normalizedRoot.endsWith('/') ? normalizedRoot : '$normalizedRoot/';
    final inside =
        candidate == normalizedRoot ||
        (normalizedRoot == '/'
            ? candidate.startsWith('/')
            : candidate.startsWith(prefix));
    if (inside && normalizedRoot.length > bestLength) {
      best = root;
      bestLength = normalizedRoot.length;
    }
  }
  return best;
}

/// Returns the drive root containing a saved path on Windows.
String? _windowsDriveRoot(String path) {
  final match = RegExp(r'^([A-Za-z]:)[\\/]').firstMatch(path);
  return match == null ? null : '${match.group(1)}\\';
}

/// Root-level file screen for a host. Restricted hosts show only the
/// effective folders the current device can access; unrestricted hosts keep
/// the platform drive/root behavior.
class HostRootView extends ConsumerStatefulWidget {
  const HostRootView({
    super.key,
    required this.host,
    required this.onSelectRoot,
    this.health,
    this.initialPath,
  });

  final Host host;
  final Health? health;
  final String? initialPath;
  final HostRootSelection onSelectRoot;

  @override
  ConsumerState<HostRootView> createState() => _HostRootViewState();
}

class _HostRootViewState extends ConsumerState<HostRootView> {
  String? _scheduledSelection;

  void _selectAfterFrame(String rootPath, String? initialPath) {
    final key = '$rootPath\u0000${initialPath ?? ''}';
    if (_scheduledSelection == key) return;
    _scheduledSelection = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSelectRoot(rootPath, initialPath);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(hostBrowsingSettingsProvider(widget.host.id));
    return settings.when(
      loading: () => _loadingScreen(context),
      error:
          (error, _) => Scaffold(
            appBar: AppBar(title: ScreenHeader(widget.host.label)),
            body: ErrorRetryCard(
              message: context.l10n.errorLabel(humanizeError(error)),
              onRetry:
                  () => ref.invalidate(
                    hostBrowsingSettingsProvider(widget.host.id),
                  ),
            ),
          ),
      data: (value) => _buildForSettings(context, value),
    );
  }

  Widget _buildForSettings(BuildContext context, AgentSettings settings) {
    if (settings.accessDenied) {
      return Scaffold(
        appBar: AppBar(title: ScreenHeader(widget.host.label)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.shieldX,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: Spacing.md),
                const Text(
                  'This device has no file access on this computer.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final os = widget.health?.os.toLowerCase() ?? '';
    final pathLooksWindows =
        widget.initialPath != null &&
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(widget.initialPath!);
    final isWindows =
        os == 'windows' ||
        pathLooksWindows ||
        settings.roots.any((root) => RegExp(r'^[A-Za-z]:[\\/]').hasMatch(root));

    if (widget.initialPath case final path?) {
      final root =
          settings.roots.isEmpty
              ? (isWindows ? _windowsDriveRoot(path) : '/')
              : allowedRootForPath(settings.roots, path, windows: isWindows);
      if (root != null) {
        _selectAfterFrame(root, path);
        return _loadingScreen(context);
      }
    }

    if (settings.roots.isNotEmpty) {
      return _AllowedRootsScreen(
        host: widget.host,
        roots: settings.roots,
        onSelect: (root) => widget.onSelectRoot(root, null),
        unavailablePath: widget.initialPath,
      );
    }

    if (isWindows) {
      return DrivesView(
        host: widget.host,
        onSelectDrive: (root) => widget.onSelectRoot(root, null),
      );
    }

    _selectAfterFrame('/', widget.initialPath);
    return _loadingScreen(context);
  }

  Widget _loadingScreen(BuildContext context) => Scaffold(
    appBar: AppBar(title: ScreenHeader(widget.host.label)),
    body: const Center(child: CircularProgressIndicator()),
  );
}

class _AllowedRootsScreen extends StatelessWidget {
  const _AllowedRootsScreen({
    required this.host,
    required this.roots,
    required this.onSelect,
    this.unavailablePath,
  });

  final Host host;
  final List<String> roots;
  final ValueChanged<String> onSelect;
  final String? unavailablePath;

  @override
  Widget build(BuildContext context) {
    final sortedRoots = [...roots]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: ScreenHeader(host.label, subtitle: 'Shared folders'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          if (unavailablePath != null) ...[
            Text(
              'This saved location is no longer available to this device. Choose a shared folder below.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: Spacing.md),
          ],
          const SectionLabel('Available folders'),
          GroupedCard(
            padded: false,
            children: [
              for (var i = 0; i < sortedRoots.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: Spacing.md),
                ListTile(
                  leading: const Icon(LucideIcons.folder),
                  title: Text(
                    folderLabel(sortedRoots[i]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    sortedRoots[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: const Icon(LucideIcons.chevronRight),
                  onTap: () => onSelect(sortedRoots[i]),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
