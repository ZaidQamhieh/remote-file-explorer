import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/agent_client.dart' show AgentApiException;
import '../../core/api/providers.dart' show clientProvider;
import '../../core/l10n_ext.dart';
import '../../core/models/host.dart';
import '../../core/models/host_app.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/screen_header.dart';
import '../../core/ui/state_views.dart';

final hostAppsProvider = FutureProvider.autoDispose
    .family<HostAppCatalog, String>((ref, hostId) async {
      final client = await ref.watch(clientProvider(hostId).future);
      return client.listApps();
    });

/// Lists the launchable apps that the paired host has chosen to expose.
/// Requests run through the host's normal pinned, authenticated client.
class HostAppsScreen extends ConsumerStatefulWidget {
  const HostAppsScreen({super.key, required this.host});

  final Host host;

  @override
  ConsumerState<HostAppsScreen> createState() => _HostAppsScreenState();
}

class _HostAppsScreenState extends ConsumerState<HostAppsScreen> {
  final Set<String> _launchingIds = <String>{};

  void _retry() => ref.invalidate(hostAppsProvider(widget.host.id));

  Future<void> _refresh() async {
    try {
      final _ = await ref.refresh(hostAppsProvider(widget.host.id).future);
    } catch (_) {
      // The provider renders the new loading/error state; don't let a refresh
      // gesture leak the request exception to Flutter's global error handler.
    }
  }

  Future<void> _launch(HostApp app) async {
    if (!_launchingIds.add(app.id)) return;
    setState(() {});
    try {
      final client = await ref.read(clientProvider(widget.host.id).future);
      await client.launchApp(app.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.hostAppLaunchStarted(app.name, widget.host.label),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = _launchFailureMessage(error, app);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _launchingIds.remove(app.id));
      } else {
        _launchingIds.remove(app.id);
      }
    }
  }

  String _launchFailureMessage(Object error, HostApp app) {
    if (error is! AgentApiException) {
      return context.l10n.hostAppLaunchFailed(app.name);
    }
    if (error.statusCode == 403) {
      return context.l10n.hostAppsLaunchDenied;
    }
    switch (error.code) {
      case 'APP_LAUNCH_BUSY':
        return context.l10n.hostAppLaunchBusy;
      case 'APP_LAUNCH_RATE_LIMITED':
        return context.l10n.hostAppLaunchRateLimited;
      case 'NO_INTERACTIVE_SESSION':
        return context.l10n.hostAppNoInteractiveSession;
      case 'APP_LAUNCH_UNAVAILABLE':
        return context.l10n.hostAppLauncherUnavailable;
      case 'APP_NOT_FOUND':
        ref.invalidate(hostAppsProvider(widget.host.id));
        return context.l10n.hostAppNoLongerAvailable;
      case 'BAD_APP_ID':
        ref.invalidate(hostAppsProvider(widget.host.id));
        return context.l10n.hostAppInvalidEntry;
      case 'APP_LAUNCH_FAILED':
        return context.l10n.hostAppLaunchFailed(app.name);
      case 'APP_CATALOG_UNSUPPORTED':
        return context.l10n.hostAppsUnsupported;
      default:
        return context.l10n.hostAppLaunchFailed(app.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appsAsync = ref.watch(hostAppsProvider(widget.host.id));
    return Scaffold(
      appBar: AppBar(
        title: ScreenHeader(
          context.l10n.hostAppsTitle,
          subtitle: widget.host.label,
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: context.l10n.hostAppsRefreshTooltip,
            icon: const Icon(LucideIcons.refreshCw),
          ),
          const SizedBox(width: Spacing.xs),
        ],
      ),
      body: appsAsync.when(
        loading:
            () => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: Spacing.md),
                  Text(context.l10n.hostAppsLoading),
                ],
              ),
            ),
        error: (error, _) {
          if (error is AgentApiException && error.statusCode == 403) {
            return _AppAccessDenied(onRetry: _retry);
          }
          if (error is AgentApiException &&
              error.code == 'APP_CATALOG_UNSUPPORTED') {
            return ErrorRetryCard(
              message: context.l10n.hostAppsUnsupported,
              onRetry: _retry,
            );
          }
          return ErrorRetryCard(
            message: context.l10n.hostAppsLoadFailed,
            onRetry: _retry,
          );
        },
        data: (catalog) {
          if (catalog.apps.isEmpty) {
            return _NoAppsView(
              onRefresh: _refresh,
              launchAllowed: catalog.launchAllowed,
            );
          }
          final showLaunchNotice = !catalog.launchAllowed;
          final instructionIndex = showLaunchNotice ? 1 : 0;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                Spacing.xl,
              ),
              itemCount: catalog.apps.length + 1 + (showLaunchNotice ? 1 : 0),
              separatorBuilder:
                  (_, index) =>
                      showLaunchNotice && index == 0
                          ? const SizedBox(height: Spacing.md2)
                          : index == instructionIndex
                          ? const SizedBox(height: Spacing.md)
                          : const SizedBox(height: Spacing.sm),
              itemBuilder: (context, index) {
                if (showLaunchNotice && index == 0) {
                  return const _LaunchAccessNotice();
                }
                if (index == instructionIndex) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
                    child: Text(
                      context.l10n.hostAppsInstruction,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                final app = catalog.apps[index - instructionIndex - 1];
                return _HostAppCard(
                  app: app,
                  launching: _launchingIds.contains(app.id),
                  launchAllowed: catalog.launchAllowed,
                  onRun: () => _launch(app),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _HostAppCard extends StatelessWidget {
  const _HostAppCard({
    required this.app,
    required this.launching,
    required this.launchAllowed,
    required this.onRun,
  });

  final HostApp app;
  final bool launching;
  final bool launchAllowed;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Spacing.md2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: Radii.cardR,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: Radii.smR,
            ),
            child: Icon(
              _iconFor(app.icon),
              color: scheme.onPrimaryContainer,
              size: 20,
            ),
          ),
          const SizedBox(width: Spacing.md2),
          Expanded(
            child: Text(
              app.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          FilledButton.tonalIcon(
            onPressed: !launchAllowed || launching ? null : onRun,
            icon:
                launching
                    ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(LucideIcons.play, size: 16),
            label: Text(
              launching
                  ? context.l10n.hostAppStartingButton
                  : context.l10n.hostAppRunButton,
            ),
          ),
        ],
      ),
    );
  }

  /// Server-provided icon values are interpreted through this allowlist. Any
  /// unknown key falls back to the same neutral computer icon.
  IconData _iconFor(String? safeIcon) => switch (safeIcon) {
    'browser' => LucideIcons.globe,
    'code' => LucideIcons.code,
    'office' => LucideIcons.fileText,
    'media' => LucideIcons.play,
    'terminal' => LucideIcons.terminal,
    'system' => LucideIcons.settings,
    _ => LucideIcons.monitor,
  };
}

class _LaunchAccessNotice extends StatelessWidget {
  const _LaunchAccessNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Spacing.md2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: Radii.smR,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.shieldAlert,
            size: 18,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              context.l10n.hostAppsLaunchPermissionOffHint,
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppAccessDenied extends StatelessWidget {
  const _AppAccessDenied({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.shieldAlert, size: 48, color: scheme.primary),
            const SizedBox(height: Spacing.md),
            Text(
              context.l10n.hostAppsAccessDeniedTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              context.l10n.hostAppsAccessDeniedMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.md),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw),
              label: Text(context.l10n.retryButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoAppsView extends StatelessWidget {
  const _NoAppsView({required this.onRefresh, required this.launchAllowed});

  final Future<void> Function() onRefresh;
  final bool launchAllowed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
          if (!launchAllowed) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md),
              child: _LaunchAccessNotice(),
            ),
            const SizedBox(height: Spacing.lg),
          ],
          Icon(LucideIcons.monitor, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: Spacing.md),
          Text(
            context.l10n.hostAppsEmptyTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Spacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Text(
              context.l10n.hostAppsEmptyMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
