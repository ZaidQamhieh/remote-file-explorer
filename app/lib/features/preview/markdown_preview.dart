import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/format.dart';
import 'preview_common.dart';
import 'text_editor.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Markdown preview: fetches the file's bytes through the pinned +
/// authenticated [AgentClient], decodes as UTF-8, and renders as formatted
/// markdown via [MarkdownBody]. Offers a raw/rendered toggle in the app bar.
class MarkdownPreviewScreen extends StatefulWidget {
  const MarkdownPreviewScreen({
    super.key,
    required this.entry,
    required this.client,
    this.chromeless = false,
  });

  final Entry entry;
  final AgentClient client;

  /// When `true`, omit the app bar so a host ([PreviewPager]) can overlay one
  /// shared top bar across sibling pages.
  final bool chromeless;

  @override
  State<MarkdownPreviewScreen> createState() => _MarkdownPreviewScreenState();
}

class _MarkdownPreviewScreenState extends State<MarkdownPreviewScreen> {
  late Future<String> _future;

  /// Whether to show raw markdown source instead of the rendered view.
  bool _showRaw = false;

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

  List<Widget> _controls() {
    return [
      IconButton(
        icon: Icon(_showRaw ? LucideIcons.code : LucideIcons.fileText),
        tooltip: _showRaw ? 'Show rendered' : 'Show raw',
        onPressed: () => setState(() => _showRaw = !_showRaw),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snapshot) {
        final body = _buildBody(context, snapshot);

        return PreviewScaffold(
          title: widget.entry.name,
          chromeless: widget.chromeless,
          actions: _controls(),
          body:
              widget.chromeless
                  ? Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: _controls(),
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
      return const PreviewLoading(message: 'Loading markdown…');
    }
    if (snapshot.hasError) {
      final err = snapshot.error;
      if (err is _TooLarge) {
        return PreviewTooLarge(sizeLabel: formatSize(err.size));
      }
      if (err is NotTextException) {
        return const PreviewError(
          message:
              "Can't preview this as markdown — "
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

    if (_showRaw) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.md),
        child: SelectableText(
          text,
          style: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontFamilyFallback: ['monospace'],
            fontSize: 13,
            height: 1.4,
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return Markdown(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        code: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontFamilyFallback: const ['monospace'],
          fontSize: 13,
          color: theme.colorScheme.onSurface,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

class _TooLarge implements Exception {
  _TooLarge(this.size);
  final int size;
}
