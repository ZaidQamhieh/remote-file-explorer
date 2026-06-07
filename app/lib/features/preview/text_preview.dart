import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/theme/tokens.dart';
import 'preview_common.dart';

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
    return _decodeAsText(bytes);
  }

  /// Decodes [bytes] as strict UTF-8. Throws [_NotText] if the content looks
  /// binary / isn't valid UTF-8, so we can show a friendly message instead
  /// of garbled output or crashing.
  String _decodeAsText(Uint8List bytes) {
    // Heuristic: NUL bytes are a strong signal of binary content.
    final sampleLen = bytes.length < 8192 ? bytes.length : 8192;
    for (var i = 0; i < sampleLen; i++) {
      if (bytes[i] == 0) throw const _NotText();
    }
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const _NotText();
    }
  }

  void _retry() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return PreviewScaffold(
      title: widget.entry.name,
      body: FutureBuilder<String>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const PreviewLoading(message: 'Loading text…');
          }
          if (snapshot.hasError) {
            final err = snapshot.error;
            if (err is _TooLarge) {
              return PreviewTooLarge(sizeLabel: formatBytes(err.size));
            }
            if (err is _NotText) {
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
        },
      ),
    );
  }
}

class _TooLarge implements Exception {
  _TooLarge(this.size);
  final int size;
}

class _NotText implements Exception {
  const _NotText();
}
