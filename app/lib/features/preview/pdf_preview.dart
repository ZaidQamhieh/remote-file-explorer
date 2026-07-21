import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/format.dart';
import 'preview_actions.dart';
import 'preview_common.dart';

/// Paginated PDF preview, fetched through the pinned + authenticated
/// [AgentClient] and rendered with `pdfx`.
class PdfPreviewScreen extends StatefulWidget {
  const PdfPreviewScreen({
    super.key,
    required this.entry,
    required this.client,
    this.host,
    this.chromeless = false,
  });

  final Entry entry;
  final AgentClient client;

  /// The host this entry lives on. Only used (optionally) to build the
  /// standalone chrome's "..." meta-sheet action — null in the rare
  /// no-siblings path where it isn't available (mostly tests).
  final Host? host;

  /// When `true`, omit the app bar so a host ([PreviewPager]) can overlay one
  /// shared top bar across sibling pages.
  final bool chromeless;

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  late Future<PdfController> _future;
  PdfController? _controller;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<PdfController> _load() async {
    final size = widget.entry.size;
    if (size != null && size > kMaxInMemoryPreviewBytes) {
      throw _TooLarge(size);
    }
    final bytes = await widget.client.fetchBytes(widget.entry.path);
    final controller = PdfController(
      document: PdfDocument.openData(Uint8List.fromList(bytes)),
    );
    _controller = controller;
    return controller;
  }

  void _retry() {
    setState(() {
      _controller?.dispose();
      _controller = null;
      _future = _load();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PreviewScaffold(
      title: widget.entry.name,
      chromeless: widget.chromeless,
      actions: previewChromeActions(
        context: context,
        entry: widget.entry,
        client: widget.client,
        host: widget.host,
      ),
      body: FutureBuilder<PdfController>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const PreviewLoading(message: 'Loading PDF…');
          }
          if (snapshot.hasError) {
            final err = snapshot.error;
            if (err is _TooLarge) {
              return PreviewTooLarge(sizeLabel: formatSize(err.size));
            }
            return PreviewError(
              message: 'Could not load this PDF.\n$err',
              onRetry: _retry,
            );
          }
          final controller = snapshot.data!;
          return Column(
            children: [
              Expanded(
                child: PdfView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  builders: PdfViewBuilders<DefaultBuilderOptions>(
                    options: const DefaultBuilderOptions(),
                    documentLoaderBuilder:
                        (_) => const PreviewLoading(message: 'Rendering PDF…'),
                    pageLoaderBuilder: (_) => const PreviewLoading(),
                    errorBuilder:
                        (_, error) => PreviewError(
                          message: 'Could not render this PDF.\n$error',
                        ),
                  ),
                ),
              ),
              // "Page N of M" caption — matches the mockup's page indicator
              // under the page thumbnail.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                child: ValueListenableBuilder<int>(
                  valueListenable: controller.pageListenable,
                  builder: (context, page, _) {
                    final total = controller.pagesCount;
                    return Text(
                      total != null ? 'Page $page of $total' : 'Page $page',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'JetBrains Mono',
                        fontFamilyFallback: const ['monospace'],
                      ),
                    );
                  },
                ),
              ),
            ],
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
