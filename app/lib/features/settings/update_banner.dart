import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/l10n_ext.dart';
import '../../core/models/app_release.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/update/auto_update.dart';
import '../../core/update/update_service.dart';
import 'update_tile.dart' show triggerUpdateInstall;

/// A passive, dismissible "Update available" banner driven by the once-per-
/// session [latestUpdateProvider]. Renders nothing unless a newer release is
/// available and the user hasn't already dismissed that version. "Update"
/// triggers the same download/install flow as [UpdateTile] directly (no
/// detour through Settings → About & Support → tapping the tile again);
/// "Dismiss" remembers this version so it won't nag again until a newer
/// build ships.
class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key});

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner> {
  bool _installing = false;

  Future<void> _startUpdate(AppRelease release) async {
    setState(() => _installing = true);
    try {
      await triggerUpdateInstall(context, release);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.updateFailed(humanizeError(e)))),
      );
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = ref.watch(latestUpdateProvider).valueOrNull;
    final dismissed = ref.watch(dismissedUpdateProvider).valueOrNull ?? 0;

    if (!shouldSurfaceUpdate(release: release, dismissedCode: dismissed)) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.sm, Spacing.sm, Spacing.sm, 0),
      child: ShadCard(
        padding: EdgeInsets.zero,
        radius: Radii.cardR,
        backgroundColor: scheme.primaryContainer,
        border: ShadBorder.all(color: Colors.transparent),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.downloadCloud,
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
                    onPressed: _installing ? null : () => _startUpdate(release),
                    child:
                        _installing
                            ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : Text(context.l10n.updateButton),
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
