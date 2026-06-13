import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/format.dart';
import 'preview_common.dart';
import 'text_editor.dart';

/// Plain-text preview: fetches the file's bytes through the pinned +
/// authenticated [AgentClient], decodes as UTF-8, and shows it in a
/// scrollable monospace, selectable view. Falls back to a friendly message
/// if the content isn't valid UTF-8 text.
class TextPreviewScreen extends StatefulWidget {
  const TextPreviewScreen({
    super.key,
    required this.entry,
    required this.client,
  });

  final Entry entry;
  final AgentClient client;

  @override
  State<TextPreviewScreen> createState() => _TextPreviewScreenState();
}

class _TextPreviewScreenState extends State<TextPreviewScreen> {
  late Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<String> _load() async {
    final size = widget.entry.size;
    if (size != null && size > kMaxInMemoryPreviewBytes) {
      throw _TooLarge(size);
    }
    final bytes = await widget.client.fetchBytes(widget.entry.path);
    return decodeAsText(bytes);
  }

  void _retry() {
    setState(() => _future = _load());
  }

  Future<void> _edit(BuildContext context, String text) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TextEditorScreen(
          entry: widget.entry,
          client: widget.client,
          initialText: text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snapshot) {
        // Only offer Edit once the text has loaded successfully and is
        // small enough for the agent's PUT /content body cap.
        final loadedText = snapshot.connectionState == ConnectionState.done &&
                !snapshot.hasError
            ? snapshot.data
            : null;
        final canEdit = loadedText != null &&
            (widget.entry.size ?? loadedText.length) <= kMaxEditableBytes;

        return PreviewScaffold(
          title: widget.entry.name,
          actions: [
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit',
                onPressed: () => _edit(context, loadedText),
              ),
          ],
          body: () {
            if (snapshot.connectionState != ConnectionState.done) {
              return const PreviewLoading(message: 'Loading text…');
            }
            if (snapshot.hasError) {
              final err = snapshot.error;
              if (err is _TooLarge) {
                return PreviewTooLarge(sizeLabel: formatSize(err.size));
              }
              if (err is NotTextException) {
                return const PreviewError(
                  message: "Can't preview this as text — "
                      "it doesn't look like a valid UTF-8 text file.",
                );
              }
              return PreviewError(
                message: 'Could not load this file.\n$err',
                onRetry: _retry,
              );
            }
            final text = snapshot.data!;
            if (text.isEmpty) {
              return Center(
                child: Text(
                  '(empty file)',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.md),
              child: SelectableText(
                text,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontFamilyFallback: ['monospace'],
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            );
          }(),
        );
      },
    );
  }
}

class _TooLarge implements Exception {
  _TooLarge(this.size);
  final int size;
}
