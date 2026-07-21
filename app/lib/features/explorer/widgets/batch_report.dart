import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/models/batch_result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/feedback.dart';
import '../../../core/ui/sheet_chrome.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Inspects a batch operation result [res] (as returned by delete/move/copy/
/// restoreTrash/batchRename) for per-item failures and either shows a
/// `$successVerb N item(s)` success snackbar, or — if anything failed — a
/// dialog listing the failed items.
///
/// Shared by the selection bar's delete action and the paste handler so the
/// conflict-resolution + execute + report flow isn't duplicated.
Future<void> reportBatchResult(
  BuildContext context,
  BatchResult res,
  String successVerb,
) async {
  final failed = res.failed;
  if (!context.mounted) return;
  if (failed.isEmpty) {
    showSuccess(
      context,
      context.l10n.batchSuccessNItems(successVerb, res.results.length),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder:
        (ctx) => Dialog(
          shape: const RoundedRectangleBorder(borderRadius: Radii.lgR),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHero(
                showGrabber: false,
                badge: Icon(
                  LucideIcons.triangleAlert,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                badgeColor: Theme.of(
                  ctx,
                ).colorScheme.error.withValues(alpha: 0.16),
                tint: Theme.of(ctx).colorScheme.error,
                title: ctx.l10n.batchResultWithErrors(
                  successVerb,
                  failed.length,
                ),
              ),
              Flexible(
                child: SizedBox(
                  width: double.maxFinite,
                  child: ListView(
                    shrinkWrap: true,
                    children:
                        failed.map((f) {
                          final msg = f.errorMessage ?? f.errorCode ?? 'failed';
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.lg,
                              vertical: 6,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f.path,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  msg,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color:
                                        Theme.of(
                                          ctx,
                                        ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.sm,
                  Spacing.md,
                  Spacing.md,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(ctx.l10n.okButton),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
  );
}
