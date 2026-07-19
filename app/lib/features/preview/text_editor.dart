import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/agent_client.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/entry.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';

/// Decodes [bytes] as strict UTF-8. Throws [NotTextException] if the content
/// looks binary / isn't valid UTF-8, so callers can show a friendly message
/// instead of garbled output or crashing.
///
/// Shared by [TextPreviewScreen] (read-only preview) and [TextEditorScreen]
/// (edit), both of which fetch raw bytes via [AgentClient.fetchBytes].
String decodeAsText(Uint8List bytes) {
  // Heuristic: NUL bytes are a strong signal of binary content.
  final sampleLen = bytes.length < 8192 ? bytes.length : 8192;
  for (var i = 0; i < sampleLen; i++) {
    if (bytes[i] == 0) throw const NotTextException();
  }
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw const NotTextException();
  }
}

/// Thrown by [decodeAsText] when the bytes don't look like valid UTF-8 text.
class NotTextException implements Exception {
  const NotTextException();
}

/// Thrown by [_TextEditorScreenState._reload] when the file's metadata
/// changed between the body fetch and the follow-up metadata check,
/// meaning the two reads can't be trusted to describe the same version.
class _InconsistentReadException implements Exception {
  const _InconsistentReadException();

  @override
  String toString() => 'File changed while reloading — try again.';
}

/// In-app text editor for files small enough to fit under the agent's
/// `PUT /v1/content` body cap ([kMaxEditableBytes]).
///
/// Loaded with the text already fetched by [TextPreviewScreen] (so opening
/// the editor doesn't re-fetch), this screen shows an editable, scrollable,
/// monospace [TextField] and a Save action that writes the new content back
/// via [AgentClient.putContent].
///
/// Optimistic concurrency: the first save sends [Entry.modified] (captured
/// when the preview loaded the file) as `baseModified`. On success, the
/// returned [Entry.modified] becomes the new `baseModified` for subsequent
/// saves. A `409 STALE_WRITE` response (the file changed on disk since)
/// offers the user a choice to reload the current on-disk content or
/// overwrite it anyway.
class TextEditorScreen extends StatefulWidget {
  const TextEditorScreen({
    super.key,
    required this.entry,
    required this.client,
    required this.initialText,
  });

  final Entry entry;
  final AgentClient client;
  final String initialText;

  @override
  State<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<TextEditorScreen> {
  late final TextEditingController _controller;
  late DateTime? _baseModified;
  bool _dirty = false;
  bool _saving = false;

  /// Bumped on every keystroke (not just the dirty transition), so a save in
  /// flight can tell whether the user typed more while it was in the air
  /// (PR-38) — clearing `_dirty` unconditionally on save success would
  /// otherwise silently mark those newer edits as saved.
  int _editRevision = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _baseModified = widget.entry.modified;
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    _editRevision++;
    if (!_dirty) {
      setState(() => _dirty = true);
    }
  }

  /// Saves the current text. If [forceOverwrite] is true, `baseModified` is
  /// omitted so the agent overwrites regardless of on-disk changes — used
  /// after the user explicitly chooses "Overwrite" on a STALE_WRITE conflict.
  Future<void> _save({bool forceOverwrite = false}) async {
    if (_saving) return;
    final revisionAtSave = _editRevision;
    setState(() => _saving = true);
    try {
      final bytes = Uint8List.fromList(utf8.encode(_controller.text));
      final updated = await widget.client.putContent(
        widget.entry.path,
        bytes,
        baseModified: forceOverwrite ? null : _baseModified,
      );
      if (!mounted) return;
      setState(() {
        _baseModified = updated.modified;
        // Only the snapshot as of revisionAtSave was actually persisted — if
        // the user kept typing during the save, newer edits are still dirty.
        _dirty = _editRevision != revisionAtSave;
        _saving = false;
      });
      showSuccess(context, context.l10n.savedFile(widget.entry.name));
    } on ReadOnlyException {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, context.l10n.readOnlyModeSaveError);
    } on StaleWriteException {
      if (!mounted) return;
      // Clear the saving flag *before* awaiting the conflict dialog — the
      // save attempt is over (it failed), and leaving the indeterminate
      // progress indicator up while the dialog is open would never settle.
      setState(() => _saving = false);
      await _resolveStaleWrite();
    } on PayloadTooLargeException {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, context.l10n.fileTooLargeToSave);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(
        context,
        context.l10n.couldNotSaveFile(humanizeError(e)),
        onRetry: _save,
      );
    }
  }

  /// The file changed on disk since [_baseModified] was captured. Offers the
  /// user a choice: reload the current on-disk content (discarding local
  /// edits) or overwrite it with the local edits anyway.
  Future<void> _resolveStaleWrite() async {
    final choice = await showShadDialog<_StaleWriteChoice>(
      context: context,
      builder:
          (ctx) => ShadDialog.alert(
            title: Text(ctx.l10n.fileChangedOnDisk),
            description: Text(ctx.l10n.staleWriteMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, _StaleWriteChoice.cancel),
                child: Text(ctx.l10n.cancelButton),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, _StaleWriteChoice.reload),
                child: Text(ctx.l10n.reloadButton),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.pop(ctx, _StaleWriteChoice.overwrite),
                child: Text(ctx.l10n.overwriteButton),
              ),
            ],
          ),
    );

    switch (choice) {
      case _StaleWriteChoice.reload:
        await _reload();
      case _StaleWriteChoice.overwrite:
        await _save(forceOverwrite: true);
      case _StaleWriteChoice.cancel:
      case null:
        break;
    }
  }

  /// Re-fetches the file's current on-disk content and metadata, discarding
  /// local edits.
  ///
  /// Body and metadata come from separate requests (`GET /content` and
  /// `GET /fs/meta`), so a write landing between them could otherwise pair
  /// one version's bytes with another version's `modified` (PR-38). Metadata
  /// is fetched again after the body and compared against the first read;
  /// a mismatch means the file changed mid-fetch, so the result is discarded
  /// as inconsistent rather than applied.
  Future<void> _reload() async {
    try {
      final before = await widget.client.meta(widget.entry.path);
      final bytes = await widget.client.fetchBytes(widget.entry.path);
      final after = await widget.client.meta(widget.entry.path);
      if (after.modified != before.modified || after.size != before.size) {
        throw const _InconsistentReadException();
      }
      final text = decodeAsText(bytes);
      if (!mounted) return;
      setState(() {
        _controller.text = text;
        _baseModified = after.modified;
        _dirty = false;
      });
      showInfo(context, context.l10n.reloadedFromHost);
    } catch (e) {
      if (!mounted) return;
      showError(
        context,
        context.l10n.couldNotReloadFile(humanizeError(e)),
        onRetry: _reload,
      );
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final discard = await showShadDialog<bool>(
      context: context,
      builder:
          (ctx) => ShadDialog.alert(
            title: Text(ctx.l10n.discardChangesTitle),
            description: Text(ctx.l10n.unsavedChangesMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.keepEditingButton),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ctx.l10n.discardButton),
              ),
            ],
          ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Also blocked while a save is in flight (PR-38): _dirty can already be
      // false at that point (no edits since the save started), but popping
      // mid-save would abandon a write whose outcome isn't known yet.
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.entry.name, overflow: TextOverflow.ellipsis),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: Spacing.md),
                child: Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(LucideIcons.save),
                tooltip: context.l10n.saveTooltip,
                onPressed: _dirty ? () => _save() : null,
              ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: TextField(
            controller: _controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: ['monospace'],
              fontSize: 13,
              height: 1.4,
            ),
            decoration: const InputDecoration(border: InputBorder.none),
          ),
        ),
      ),
    );
  }
}

enum _StaleWriteChoice { cancel, reload, overwrite }
