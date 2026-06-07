import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import 'image_preview.dart';
import 'pdf_preview.dart';
import 'text_preview.dart';
import 'video_preview.dart';

enum _PreviewKind { image, pdf, video, text, none }

const Set<String> _textExtensions = {
  'txt', 'md', 'markdown', 'json', 'yaml', 'yml', 'xml', 'csv', 'tsv', 'log',
  'ini', 'cfg', 'conf', 'toml', 'env',
  // source code
  'dart', 'go', 'py', 'js', 'jsx', 'ts', 'tsx', 'java', 'kt', 'kts', 'c', 'h',
  'cpp', 'hpp', 'cc', 'cs', 'rs', 'rb', 'php', 'swift', 'sh', 'bash', 'zsh',
  'sql', 'gradle', 'properties', 'gitignore', 'dockerfile', 'makefile',
  'html', 'htm', 'css', 'scss', 'less', 'vue', 'svelte',
};

const Set<String> _imageExtensions = {
  'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'heic', 'heif',
};

const Set<String> _videoExtensions = {
  'mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v', '3gp',
};

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

_PreviewKind _kindOf(Entry entry) {
  final mime = entry.mimeType?.toLowerCase();
  final ext = _extensionOf(entry.name);

  if (mime != null) {
    if (mime.startsWith('image/')) return _PreviewKind.image;
    if (mime == 'application/pdf') return _PreviewKind.pdf;
    if (mime.startsWith('video/')) return _PreviewKind.video;
    if (mime.startsWith('text/')) return _PreviewKind.text;
    if (mime == 'application/json' ||
        mime == 'application/xml' ||
        mime == 'application/x-yaml' ||
        mime.endsWith('+json') ||
        mime.endsWith('+xml')) {
      return _PreviewKind.text;
    }
  }

  // Fall back to file extension when the mime type is missing/unhelpful.
  if (_imageExtensions.contains(ext)) return _PreviewKind.image;
  if (ext == 'pdf') return _PreviewKind.pdf;
  if (_videoExtensions.contains(ext)) return _PreviewKind.video;
  if (_textExtensions.contains(ext)) return _PreviewKind.text;

  return _PreviewKind.none;
}

/// Whether [entry] has a known preview viewer (used to decide whether to
/// show a "Preview" action for it).
bool isPreviewable(Entry entry) {
  if (entry.isDir) return false;
  return _kindOf(entry) != _PreviewKind.none;
}

/// Opens the appropriate in-app preview viewer for [entry], based on its
/// MIME type (falling back to file extension). Shows a snackbar if there's
/// no preview available for this file type.
///
/// All preview content is fetched through [client] — the pinned,
/// authenticated `AgentClient` — never via plain network requests, since the
/// agent uses a self-signed certificate and bearer-token auth.
Future<void> openPreview(
  BuildContext context, {
  required Entry entry,
  required Host host,
  required AgentClient client,
}) async {
  if (entry.isDir) return;

  final kind = _kindOf(entry);
  Widget? screen;
  switch (kind) {
    case _PreviewKind.image:
      screen = ImagePreviewScreen(entry: entry, client: client);
      break;
    case _PreviewKind.pdf:
      screen = PdfPreviewScreen(entry: entry, client: client);
      break;
    case _PreviewKind.video:
      screen = VideoPreviewScreen(entry: entry, client: client);
      break;
    case _PreviewKind.text:
      screen = TextPreviewScreen(entry: entry, client: client);
      break;
    case _PreviewKind.none:
      screen = null;
      break;
  }

  if (screen == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No preview available for this file type')),
    );
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => screen!),
  );
}
