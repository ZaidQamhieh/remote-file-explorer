import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/ui/feedback.dart';

/// Inspects a batch operation result [res] (the JSON body returned by
/// delete/move/copy — a `results` list of `{path, ok, error?}`) for per-item
/// failures and either shows a `$successVerb N item(s)` success snackbar, or
/// — if anything failed — a dialog listing the failed items.
///
/// Shared by the selection bar's delete action and the paste handler so the
/// conflict-resolution + execute + report flow isn't duplicated.
Future<void> reportBatchResult(
  BuildContext context,
  Map<String, dynamic> res,
  String successVerb,
) async {
  final results = (res['results'] as List?) ?? const [];
  final failed =
      results.whereType<Map>().where((r) => r['ok'] == false).toList();
  if (!context.mounted) return;
  if (failed.isEmpty) {
    final n = results.length;
    showSuccess(context, context.l10n.batchSuccessNItems(successVerb, n));
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
                    final err = f['error'];
                    final msg =
                        err is Map
                            ? (err['message'] ?? err['code'] ?? 'failed')
                            : 'failed';
                    return ListTile(
                      dense: true,
                      title: Text('${f['path'] ?? '?'}'),
                      subtitle: Text('$msg'),
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
