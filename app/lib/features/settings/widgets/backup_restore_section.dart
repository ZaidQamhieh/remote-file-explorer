import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/backup/backup_service.dart';
import '../../../core/l10n_ext.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/storage/favorites.dart';
import '../../../core/storage/host_store.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/feedback.dart';
import 'settings_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// **Backup & restore** (N1) — export the app's full local state (paired
/// hosts, device tokens, cert fingerprints, favorites, all settings) to a
/// passphrase-encrypted file, and import it back to restore on a
/// reinstalled/new phone.
class BackupRestoreSection extends ConsumerWidget {
  const BackupRestoreSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsSection(
      title: context.l10n.backupRestoreSection,
      icon: LucideIcons.shield,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(LucideIcons.fileUp),
          title: Text(context.l10n.exportConfig),
          subtitle: Text(context.l10n.exportConfigSubtitle),
          onTap: () => _exportConfig(context, ref),
        ),
        const Divider(height: Spacing.lg),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(LucideIcons.download),
          title: Text(context.l10n.importConfig),
          subtitle: Text(context.l10n.importConfigSubtitle),
          onTap: () => _importConfig(context, ref),
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          context.l10n.backupEncryptionWarning,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  Future<void> _exportConfig(BuildContext context, WidgetRef ref) async {
    final passphrase = await _promptPassphrase(
      context,
      title: context.l10n.exportConfigTitle,
      confirm: true,
    );
    if (passphrase == null || !context.mounted) return;

    await runWithFeedback<bool>(
      context,
      () async {
        final service = await ref.read(backupServiceProvider.future);
        final envelope = await service.exportToEnvelope(passphrase);

        final dir = await getTemporaryDirectory();
        final stamp = _timestamp(DateTime.now());
        final file = File('${dir.path}/rfe-backup-$stamp.rfebackup');
        await file.writeAsString(envelope);

        await Share.shareXFiles([XFile(file.path)]);
        return true;
      },
      running: context.l10n.preparingBackup,
      success: (_) => context.l10n.backupReadyToShare,
      error: context.l10n.exportFailed,
    );
  }

  // ---------------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------------

  Future<void> _importConfig(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    String envelope;
    try {
      envelope = await File(path).readAsString();
    } catch (e) {
      if (context.mounted) {
        showError(context, context.l10n.couldNotReadFile(humanizeError(e)));
      }
      return;
    }

    if (!context.mounted) return;
    final passphrase = await _promptPassphrase(
      context,
      title: context.l10n.importConfigTitle,
      confirm: false,
    );
    if (passphrase == null || !context.mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(ctx.l10n.replaceCurrentConfig),
            content: Text(ctx.l10n.importWarningMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.cancelButton),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ctx.l10n.replaceButton),
              ),
            ],
          ),
    );
    if (proceed != true || !context.mounted) return;

    final ok = await runWithFeedback<bool>(
      context,
      () async {
        final service = await ref.read(backupServiceProvider.future);
        await service.importFromEnvelope(envelope, passphrase);
        return true;
      },
      running: context.l10n.restoringConfig,
      success: (_) => context.l10n.configRestored,
      error: context.l10n.importFailed,
    );
    if (ok != true || !context.mounted) return;

    ref.invalidate(hostStoreProvider);
    ref.invalidate(favoritesProvider);
    ref.invalidate(settingsProvider);

    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ---------------------------------------------------------------------------
  // Passphrase dialog
  // ---------------------------------------------------------------------------

  /// Prompts for a passphrase. When [confirm] is true (export), shows a second
  /// "confirm passphrase" field and requires both to match and be at least 6
  /// characters. When false (import), a single field is shown with no length
  /// check (the file's own passphrase determines validity).
  ///
  /// Returns the passphrase, or `null` if cancelled.
  Future<String?> _promptPassphrase(
    BuildContext context, {
    required String title,
    required bool confirm,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _PassphraseDialog(title: title, confirm: confirm),
    );
  }

  static String _timestamp(DateTime t) {
    final y = t.year.toString().padLeft(4, '0');
    final m = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$y$m$d-$hh$mm';
  }
}

/// Modal dialog collecting a passphrase (and, for export, a confirmation
/// field). Validates on submit: minimum 6 characters, and (when [confirm] is
/// set) both fields must match.
class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({required this.title, required this.confirm});

  final String title;
  final bool confirm;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final pass = _passCtrl.text;
    if (pass.length < 6) {
      setState(() => _error = context.l10n.passphraseMinLength);
      return;
    }
    if (widget.confirm && pass != _confirmCtrl.text) {
      setState(() => _error = context.l10n.passphraseMismatch);
      return;
    }
    Navigator.of(context).pop(pass);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _passCtrl,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.l10n.passphraseLabel,
            ),
            onSubmitted: widget.confirm ? null : (_) => _submit(),
          ),
          if (widget.confirm) ...[
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: context.l10n.confirmPassphraseLabel,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancelButton),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(context.l10n.continueButton),
        ),
      ],
    );
  }
}
