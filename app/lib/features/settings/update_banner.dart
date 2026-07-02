import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/tokens.dart';
import '../../core/update/auto_update.dart';
import '../../core/update/update_service.dart';
import '../home/home_state.dart';

/// A passive, dismissible "Update available" banner driven by the once-per-
/// session [latestUpdateProvider]. Renders nothing unless a newer release is
/// available and the user hasn't already dismissed that version. "Update"
/// opens App Settings (where [UpdateTile] performs the download/install);
/// "Dismiss" remembers this version so it won't nag again until a newer build
/// ships.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final release = ref.watch(latestUpdateProvider).valueOrNull;
    final dismissed = ref.watch(dismissedUpdateProvider).valueOrNull ?? 0;

    if (!shouldSurfaceUpdate(release: release, dismissedCode: dismissed)) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.sm, Spacing.sm, Spacing.sm, 0),
      child: Card(
        color: scheme.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: Radii.cardR),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.system_update_rounded,
                    color: scheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      context.l10n.updateAvailable(release!.versionName),
                      style: textTheme.titleSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        () => ref
                            .read(dismissedUpdateProvider.notifier)
                            .dismiss(release.versionCode),
                    child: Text(context.l10n.dismissButton),
                  ),
                  const SizedBox(width: Spacing.xs),
                  FilledButton(
                    onPressed:
                        () =>
                            ref.read(selectedTabIndexProvider.notifier).state =
                                3,
                    child: Text(context.l10n.updateButton),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
