import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
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
    if (!_dirty) {
      setState(() => _dirty = true);
    }
  }

  /// Saves the current text. If [forceOverwrite] is true, `baseModified` is
  /// omitted so the agent overwrites regardless of on-disk changes — used
  /// after the user explicitly chooses "Overwrite" on a STALE_WRITE conflict.
  Future<void> _save({bool forceOverwrite = false}) async {
    if (_saving) return;
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
        _dirty = false;
        _saving = false;
      });
      showSuccess(context, 'Saved "${widget.entry.name}"');
    } on ReadOnlyException {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, 'This host is in read-only mode — changes can\'t be saved.');
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
      showError(context, 'This file is too large to save.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, 'Could not save this file.\n$e', onRetry: _save);
    }
  }

  /// The file changed on disk since [_baseModified] was captured. Offers the
  /// user a choice: reload the current on-disk content (discarding local
  /// edits) or overwrite it with the local edits anyway.
  Future<void> _resolveStaleWrite() async {
    final choice = await showDialog<_StaleWriteChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('File changed on disk'),
        content: const Text(
          'This file was modified on the host since you opened it. '
          'You can reload the current version (your edits here will be '
          'lost) or overwrite it with your edits.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _StaleWriteChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _StaleWriteChoice.reload),
            child: const Text('Reload'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _StaleWriteChoice.overwrite),
            child: const Text('Overwrite'),
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
  Future<void> _reload() async {
    try {
      final bytes = await widget.client.fetchBytes(widget.entry.path);
      final entry = await widget.client.meta(widget.entry.path);
      final text = decodeAsText(bytes);
      if (!mounted) return;
      setState(() {
        _controller.text = text;
        _baseModified = entry.modified;
        _dirty = false;
      });
      showInfo(context, 'Reloaded the current version from the host');
    } catch (e) {
      if (!mounted) return;
      showError(context, 'Could not reload this file.\n$e', onRetry: _reload);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes that will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
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
                icon: const Icon(Icons.save_outlined),
                tooltip: 'Save',
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
            decoration: const InputDecoration(
              border: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }
}

enum _StaleWriteChoice { cancel, reload, overwrite }
