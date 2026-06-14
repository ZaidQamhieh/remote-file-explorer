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
import '../../core/models/drive.dart';
import '../../core/models/host.dart';
import '../../core/storage/favorites.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/state_views.dart';
import 'explorer_screen.dart';
import 'explorer_state.dart' show buildPathStack, folderLabel;
import 'widgets/favorites_pin_row.dart';

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
      appBar: AppBar(title: Text(host.label)),
      body: drivesAsync.when(
        loading: () => const ListingSkeleton(),
        error:
            (e, _) => ErrorRetryCard(
              message: 'Could not load drives: $e',
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
                child: ListView.builder(
                  padding: const EdgeInsets.all(Spacing.md),
                  itemCount: drives.length,
                  itemBuilder:
                      (context, i) => _DriveTile(drive: drives[i], host: host),
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
    showInfo(context, 'Removed "${fav.label}" from favorites');
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

    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: Radii.cardR),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: Radii.cardR),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: Radii.smR,
          ),
          alignment: Alignment.center,
          child: Icon(Icons.storage_rounded, color: scheme.onSurfaceVariant),
        ),
        title: Text(label, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          hasCapacity
              ? '${formatSize(free)} free of ${formatSize(total)}  ·  ${drive.path}'
              : drive.path,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap:
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder:
                    (_) => ExplorerScreen(host: host, rootPath: drive.path),
              ),
            ),
      ),
    );
  }
}
