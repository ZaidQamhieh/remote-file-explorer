import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/agent_client.dart' show AgentApiException;
import '../../core/api/providers.dart' show clientProvider;
import '../../core/l10n_ext.dart';
import '../../core/models/host.dart';
import '../../core/models/host_app.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _retry() => ref.invalidate(hostAppsProvider(widget.host.id));

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

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
      case 'APP_NOT_LAUNCHABLE':
        return context.l10n.hostAppCannotRun;
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
            message:
                '${context.l10n.hostAppsLoadFailed}\n${humanizeError(error)}',
            onRetry: _retry,
          );
        },
        data: (catalog) {
          if (catalog.apps.isEmpty) {
            return _NoAppsView(
              onRefresh: _refresh,
              launchAllowed: catalog.launchAllowed,
              platform: _platformLabel(catalog.platform),
            );
          }
          final query = _searchQuery.trim().toLowerCase();
          final visibleApps =
              query.isEmpty
                  ? catalog.apps
                  : catalog.apps
                      .where((app) {
                        return app.name.toLowerCase().contains(query) ||
                            (app.description?.toLowerCase().contains(query) ??
                                false);
                      })
                      .toList(growable: false);
          final showLaunchNotice = !catalog.launchAllowed;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.md,
                    Spacing.md,
                    0,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (showLaunchNotice) ...[
                        const _LaunchAccessNotice(),
                        const SizedBox(height: Spacing.md),
                      ],
                      _CatalogSummary(
                        platform: _platformLabel(catalog.platform),
                        appCount: catalog.apps.length,
                      ),
                      const SizedBox(height: Spacing.md),
                      TextField(
                        key: const Key('host-apps-search'),
                        controller: _searchController,
                        onChanged:
                            (value) => setState(() => _searchQuery = value),
                        textInputAction: TextInputAction.search,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          hintText: context.l10n.hostAppsSearchHint,
                          prefixIcon: const Icon(LucideIcons.search),
                          suffixIcon:
                              _searchQuery.isEmpty
                                  ? null
                                  : IconButton(
                                    tooltip:
                                        context.l10n.hostAppsClearSearchTooltip,
                                    onPressed: _clearSearch,
                                    icon: const Icon(LucideIcons.x),
                                  ),
                          filled: true,
                        ),
                      ),
                      const SizedBox(height: Spacing.md),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.xs,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.l10n.hostAppsInstruction,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.copyWith(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (query.isNotEmpty)
                              Text(
                                context.l10n.hostAppsMatches(
                                  visibleApps.length,
                                ),
                                style: Theme.of(
                                  context,
                                ).textTheme.labelMedium?.copyWith(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (visibleApps.isEmpty) ...[
                        const SizedBox(height: Spacing.md),
                        _NoSearchResultsView(onClear: _clearSearch),
                      ],
                    ]),
                  ),
                ),
                if (visibleApps.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.md,
                      Spacing.sm,
                      Spacing.md,
                      Spacing.xl,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final app = visibleApps[index];
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom:
                                index == visibleApps.length - 1
                                    ? 0
                                    : Spacing.sm,
                          ),
                          child: _HostAppCard(
                            app: app,
                            launching: _launchingIds.contains(app.id),
                            launchAllowed: catalog.launchAllowed,
                            onRun: () => _launch(app),
                          ),
                        );
                      }, childCount: visibleApps.length),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _platformLabel(String platform) => switch (platform.toLowerCase()) {
    'windows' => context.l10n.hostAppsPlatformWindows,
    'linux' => context.l10n.hostAppsPlatformLinux,
    'darwin' => context.l10n.hostAppsPlatformMacOS,
    _ => context.l10n.hostAppsPlatformUnknown,
  };
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (!app.launchable) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(
                    context.l10n.hostAppCannotRun,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (app.description?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(
                    app.description!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          FilledButton.tonalIcon(
            onPressed:
                !launchAllowed || !app.launchable || launching ? null : onRun,
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
  const _NoAppsView({
    required this.onRefresh,
    required this.launchAllowed,
    required this.platform,
  });

  final Future<void> Function() onRefresh;
  final bool launchAllowed;
  final String platform;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.xl,
        ),
        children: [
          if (!launchAllowed) ...[
            const _LaunchAccessNotice(),
            const SizedBox(height: Spacing.md),
          ],
          _CatalogSummary(platform: platform, appCount: 0),
          const SizedBox(height: Spacing.xl),
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

class _CatalogSummary extends StatelessWidget {
  const _CatalogSummary({required this.platform, required this.appCount});

  final String platform;
  final int appCount;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: Radii.smR,
            ),
            child: Icon(
              LucideIcons.monitor,
              color: scheme.onPrimaryContainer,
              size: 20,
            ),
          ),
          const SizedBox(width: Spacing.md2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.hostAppsCatalogTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  context.l10n.hostAppsCatalogPlatform(platform),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  context.l10n.hostAppsCatalogScope,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md2,
              vertical: Spacing.xs,
            ),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: Radii.stadiumR,
            ),
            child: Text(
              context.l10n.hostAppsCount(appCount),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoSearchResultsView extends StatelessWidget {
  const _NoSearchResultsView({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: Radii.cardR,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.searchX, size: 32, color: scheme.onSurfaceVariant),
          const SizedBox(height: Spacing.sm),
          Text(
            context.l10n.hostAppsNoMatchesTitle,
            style: Theme.of(context).textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            context.l10n.hostAppsNoMatchesMessage,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.md),
          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(LucideIcons.x, size: 16),
            label: Text(context.l10n.hostAppsClearSearchTooltip),
          ),
        ],
      ),
    );
  }
}
