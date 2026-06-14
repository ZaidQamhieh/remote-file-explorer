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
///
/// Offers an Edit affordance (small files only) and a **line-numbers** toggle
/// that shows/hides a left gutter of 1-based line numbers alongside the text.
/// Syntax highlighting is intentionally out of scope (no highlighting package).
class TextPreviewScreen extends StatefulWidget {
  const TextPreviewScreen({
    super.key,
    required this.entry,
    required this.client,
    this.chromeless = false,
  });

  final Entry entry;
  final AgentClient client;

  /// When `true`, omit the app bar so a host ([PreviewPager]) can overlay one
  /// shared top bar across sibling pages. The Edit + line-numbers controls then
  /// render as a compact strip pinned above the text body instead.
  final bool chromeless;

  @override
  State<TextPreviewScreen> createState() => _TextPreviewScreenState();
}

class _TextPreviewScreenState extends State<TextPreviewScreen> {
  late Future<String> _future;

  /// Whether the left line-number gutter is shown. Off by default — most
  /// readers don't need it, and it costs horizontal space on a phone.
  bool _showLineNumbers = false;

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

  /// The Edit + line-numbers toggle controls, shared between the standalone
  /// app bar and the chromeless inline strip. [loadedText] is non-null only
  /// once the file loaded and is small enough to edit.
  List<Widget> _controls(BuildContext context, String? loadedText) {
    final canEdit = loadedText != null &&
        (widget.entry.size ?? loadedText.length) <= kMaxEditableBytes;
    return [
      IconButton(
        icon: Icon(_showLineNumbers
            ? Icons.format_list_numbered
            : Icons.format_list_numbered_outlined),
        tooltip: _showLineNumbers ? 'Hide line numbers' : 'Show line numbers',
        isSelected: _showLineNumbers,
        onPressed: () => setState(() => _showLineNumbers = !_showLineNumbers),
      ),
      if (canEdit)
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Edit',
          onPressed: () => _edit(context, loadedText),
        ),
    ];
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

        final body = _buildBody(context, snapshot);

        return PreviewScaffold(
          title: widget.entry.name,
          chromeless: widget.chromeless,
          actions: _controls(context, loadedText),
          body: widget.chromeless
              ? Column(
                  children: [
                    // Inline control strip standing in for the app-bar actions
                    // when the pager owns the (shared) top bar.
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _controls(context, loadedText),
                      ),
                    ),
                    Expanded(child: body),
                  ],
                )
              : body,
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, AsyncSnapshot<String> snapshot) {
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
      child: _showLineNumbers
          ? _NumberedText(text: text)
          : SelectableText(
              text,
              style: _kMono,
            ),
    );
  }
}

/// The monospace text style shared by the plain and line-numbered views.
const TextStyle _kMono = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['monospace'],
  fontSize: 13,
  height: 1.4,
);

/// Renders [text] with a left gutter of right-aligned 1-based line numbers in
/// the same monospace metrics, so numbers line up with their rows. The text
/// stays selectable; the gutter is dimmed and not selectable.
class _NumberedText extends StatelessWidget {
  const _NumberedText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = text.split('\n');
    final gutter = [
      for (var i = 0; i < lines.length; i++) '${i + 1}',
    ].join('\n');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: Spacing.md),
          child: Text(
            gutter,
            textAlign: TextAlign.right,
            style: _kMono.copyWith(color: scheme.outline),
          ),
        ),
        Expanded(
          child: SelectableText(text, style: _kMono),
        ),
      ],
    );
  }
}

class _TooLarge implements Exception {
  _TooLarge(this.size);
  final int size;
}
