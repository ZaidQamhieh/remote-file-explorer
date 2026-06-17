/// Shared prompt shown when a copy/move/upload would land on a name that
/// already exists in the destination directory.
///
/// One choice applies to the whole batch (no per-item UI in v1):
/// - [ConflictResolution.keepBoth] — auto-rename the colliding item(s).
/// - [ConflictResolution.overwrite] — replace the existing item(s).
/// - [ConflictResolution.skip] — drop the colliding item(s) from the batch.
/// - [ConflictResolution.cancel] — abort the whole operation.
library;

import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';

/// The user's choice for resolving one or more name collisions.
enum ConflictResolution {
  /// Auto-rename the colliding item(s) so both copies are kept.
  keepBoth,

  /// Replace the existing item(s) at the destination.
  overwrite,

  /// Drop the colliding item(s) from the batch and proceed with the rest.
  skip,

  /// Abort the operation entirely.
  cancel,
}

/// Shows an M3 [AlertDialog] explaining that [collidingCount] of
/// [totalCount] items already exist in [destLabel], offering **Keep both**,
/// **Overwrite**, **Skip these**, and **Cancel**.
///
/// Returns the chosen [ConflictResolution], or [ConflictResolution.cancel]
/// if the dialog is dismissed (e.g. tapping outside or the back gesture) —
/// callers don't need to special-case a `null` result.
Future<ConflictResolution> showConflictResolutionDialog(
  BuildContext context, {
  required int collidingCount,
  required int totalCount,
  required String destLabel,
}) async {
  final result = await showDialog<ConflictResolution>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          title: Text(ctx.l10n.nameConflictTitle),
          content: Text(
            ctx.l10n.nameConflictBody(collidingCount, totalCount, destLabel),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, ConflictResolution.cancel),
              child: Text(ctx.l10n.cancelButton),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ConflictResolution.skip),
              child: Text(ctx.l10n.skipTheseButton),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ConflictResolution.keepBoth),
              child: Text(ctx.l10n.keepBothButton),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ConflictResolution.overwrite),
              child: Text(ctx.l10n.overwriteButton),
            ),
          ],
        ),
  );
  return result ?? ConflictResolution.cancel;
}
