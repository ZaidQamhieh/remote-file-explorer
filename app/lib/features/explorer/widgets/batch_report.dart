import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/models/batch_result.dart';
import '../../../core/ui/feedback.dart';

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
        (ctx) => AlertDialog(
          title: Text(
            ctx.l10n.batchResultWithErrors(successVerb, failed.length),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children:
                  failed.map((f) {
                    final msg = f.errorMessage ?? f.errorCode ?? 'failed';
                    return ListTile(
                      dense: true,
                      title: Text(f.path),
                      subtitle: Text(msg),
                    );
                  }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.l10n.okButton),
            ),
          ],
        ),
  );
}
