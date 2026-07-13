/// Root screen shown for Windows hosts: lists the host's drives
/// (`AgentClient.drives()`) instead of a `/`-rooted file listing, since `/` is
/// not a meaningful path on Windows.
///
/// Tapping a drive opens [ExplorerScreen] rooted at that drive's path (e.g.
/// `C:\`); popping back from a drive's root returns here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/drive.dart';
import '../../core/models/host.dart';
import '../../core/storage/favorites.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/grouped_card.dart';
import '../../core/ui/screen_header.dart';
import '../../core/ui/state_views.dart';
import 'explorer_screen.dart';
import 'explorer_state.dart' show buildPathStack, folderLabel;
import 'widgets/favorites_pin_row.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Fetches the drive list for [hostId] via the shared [clientProvider].
/// `autoDispose` so it's refetched each time the drives screen is opened.
final drivesProvider = FutureProvider.autoDispose.family<List<Drive>, String>((
  ref,
  hostId,
) async {
  final client = await ref.watch(clientProvider(hostId).future);
  return client.drives();
});

class DrivesView extends ConsumerWidget {
  const DrivesView({super.key, required this.host});

  final Host host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drivesAsync = ref.watch(drivesProvider(host.id));
    final favs =
        ref
            .watch(favoritesProvider)
            .valueOrNull
            ?.where((f) => f.hostId == host.id)
            .toList() ??
        const [];

    return Scaffold(
      appBar: AppBar(toolbarHeight: 72, title: ScreenHeader(host.label)),
      body: drivesAsync.when(
        loading: () => const ListingSkeleton(),
        error:
            (e, _) => ErrorRetryCard(
              message: context.l10n.couldNotLoadDrives(humanizeError(e)),
              onRetry: () => ref.invalidate(drivesProvider(host.id)),
            ),
        data: (drives) {
          if (drives.isEmpty) {
            return const EmptyFolderView();
          }
          return Column(
            children: [
              if (favs.isNotEmpty)
                FavoritesPinRow(
                  favorites: favs,
                  onOpen: (fav) => _openFavorite(context, fav),
                  onRemove: (fav) => _removeFavorite(context, ref, fav),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(Spacing.md),
                  children: [
                    GroupedCard(
                      padded: false,
                      children: [
                        for (int i = 0; i < drives.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: Spacing.md,
                              endIndent: Spacing.md,
                              color:
                                  Theme.of(context).colorScheme.outlineVariant,
                            ),
                          _DriveTile(drive: drives[i], host: host),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Opens [ExplorerScreen] rooted at the favorite's drive and jumps straight
  /// to its path.
  void _openFavorite(BuildContext context, Favorite fav) {
    final driveRoot = buildPathStack(fav.path).first;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ExplorerScreen(
              host: host,
              rootPath: driveRoot,
              initialPath: fav.path,
            ),
      ),
    );
  }

  void _removeFavorite(BuildContext context, WidgetRef ref, Favorite fav) {
    ref.read(favoritesProvider.notifier).remove(fav.hostId, fav.path);
    showInfo(context, context.l10n.removedFavorite(fav.label));
  }
}

class _DriveTile extends StatelessWidget {
  const _DriveTile({required this.drive, required this.host});

  final Drive drive;
  final Host host;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label =
        (drive.label != null && drive.label!.isNotEmpty)
            ? drive.label!
            : folderLabel(drive.path);
    final total = drive.totalBytes;
    final free = drive.freeBytes;
    final hasCapacity = total != null && free != null;

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: Radii.smR,
        ),
        alignment: Alignment.center,
        child: Icon(LucideIcons.hardDrive, color: scheme.onSurfaceVariant),
      ),
      title: Text(label, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        hasCapacity
            ? '${formatSize(free)} free of ${formatSize(total)}  ·  ${drive.path}'
            : drive.path,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(LucideIcons.chevronRight),
      onTap:
          () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ExplorerScreen(host: host, rootPath: drive.path),
            ),
          ),
    );
  }
}
