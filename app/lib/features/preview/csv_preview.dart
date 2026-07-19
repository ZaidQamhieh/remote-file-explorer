import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/format.dart';
import 'preview_common.dart';
import 'text_editor.dart';

/// Maximum number of rows to render in the CSV table. Beyond this we truncate
/// and show a row-count indicator — rendering 100k rows in a DataTable would
/// freeze the UI.
const int kMaxCsvRows = 1000;

/// CSV preview: fetches the file's bytes through the pinned +
/// authenticated [AgentClient], decodes as UTF-8, parses into rows via
/// [parseCsvRows] (quote-aware, RFC 4180-ish), and renders as a
/// horizontally-scrollable [DataTable].
///
/// PR-67 (partial): parsing now correctly handles quoted commas, escaped
/// quotes, and embedded newlines instead of naively splitting on `\n` then
/// `,`. Still parses the whole file synchronously on the UI isolate rather
/// than streaming/off-isolate — that half of the finding (medium CSVs can
/// block the UI while parsing) is unaddressed this pass.
class CsvPreviewScreen extends StatefulWidget {
  const CsvPreviewScreen({
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
  State<CsvPreviewScreen> createState() => _CsvPreviewScreenState();
}

class _CsvPreviewScreenState extends State<CsvPreviewScreen> {
  late Future<_CsvData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_CsvData> _load() async {
    final size = widget.entry.size;
    if (size != null && size > kMaxInMemoryPreviewBytes) {
      throw _TooLarge(size);
    }
    final bytes = await widget.client.fetchBytes(widget.entry.path);
    final text = decodeAsText(bytes);
    return _parseCsv(text);
  }

  void _retry() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CsvData>(
      future: _future,
      builder: (context, snapshot) {
        final body = _buildBody(context, snapshot);
        final totalRows = snapshot.data?.totalRows;
        final subtitle =
            totalRows != null
                ? '$totalRows row${totalRows == 1 ? '' : 's'}'
                : null;

        return PreviewScaffold(
          title: widget.entry.name,
          chromeless: widget.chromeless,
          actions: [
            if (subtitle != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: Spacing.md),
                  child: Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
          ],
          body:
              widget.chromeless
                  ? Column(
                    children: [
                      if (subtitle != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              right: Spacing.md,
                              top: Spacing.xs,
                            ),
                            child: Text(
                              subtitle,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
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

  Widget _buildBody(BuildContext context, AsyncSnapshot<_CsvData> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const PreviewLoading(message: 'Loading CSV…');
    }
    if (snapshot.hasError) {
      final err = snapshot.error;
      if (err is _TooLarge) {
        return PreviewTooLarge(sizeLabel: formatSize(err.size));
      }
      if (err is NotTextException) {
        return const PreviewError(
          message:
              "Can't preview this as CSV — "
              "it doesn't look like a valid UTF-8 text file.",
        );
      }
      return PreviewError(
        message: 'Could not load this file.\n$err',
        onRetry: _retry,
      );
    }
    final data = snapshot.data!;
    if (data.headers.isEmpty && data.rows.isEmpty) {
      return Center(
        child: Text(
          '(empty file)',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }

    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.md),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            theme.colorScheme.surfaceContainerHighest,
          ),
          columns: [
            for (final h in data.headers)
              DataColumn(
                label: Text(
                  h,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
          rows: [
            for (final row in data.rows)
              DataRow(
                cells: [
                  for (var i = 0; i < data.headers.length; i++)
                    DataCell(Text(i < row.length ? row[i] : '')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Parsed CSV content: a header row and up to [kMaxCsvRows] data rows,
/// plus the total row count (before truncation) for the subtitle.
class _CsvData {
  _CsvData({
    required this.headers,
    required this.rows,
    required this.totalRows,
  });

  final List<String> headers;
  final List<List<String>> rows;

  /// Total data rows in the file (may exceed [rows.length] if truncated).
  final int totalRows;
}

/// Parses [text] into a [_CsvData]. The first row becomes headers; remaining
/// rows become data rows, capped at [kMaxCsvRows].
_CsvData _parseCsv(String text) {
  final rows = parseCsvRows(text);
  if (rows.isEmpty) {
    return _CsvData(headers: [], rows: [], totalRows: 0);
  }

  final headers = rows.first;
  final dataRows = rows.skip(1).toList();
  final totalRows = dataRows.length;
  final capped =
      dataRows.length > kMaxCsvRows
          ? dataRows.sublist(0, kMaxCsvRows)
          : dataRows;

  return _CsvData(headers: headers, rows: capped, totalRows: totalRows);
}

/// Parses [text] as CSV into rows of cells, RFC 4180-ish: a field opening
/// with `"` may contain commas, `\r`/`\n`, and a doubled `""` as an escaped
/// literal quote, ending at the next unescaped `"`. Unquoted fields are
/// trimmed (matching the previous naive parser's behavior); quoted field
/// content is preserved exactly. Blank lines are dropped. Exported for unit
/// testing.
List<List<String>> parseCsvRows(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var fieldQuoted = false;

  void endField() {
    row.add(fieldQuoted ? field.toString() : field.toString().trim());
    field.clear();
    fieldQuoted = false;
  }

  void endRow() {
    endField();
    if (!(row.length == 1 && row.first.isEmpty)) {
      rows.add(row);
    }
    row = [];
  }

  var i = 0;
  final len = text.length;
  while (i < len) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < len && text[i + 1] == '"') {
          field.write('"');
          i += 2;
        } else {
          inQuotes = false;
          i++;
        }
      } else {
        field.write(c);
        i++;
      }
      continue;
    }
    if (c == '"' && field.isEmpty) {
      inQuotes = true;
      fieldQuoted = true;
      i++;
    } else if (c == ',') {
      endField();
      i++;
    } else if (c == '\r') {
      i++;
    } else if (c == '\n') {
      endRow();
      i++;
    } else {
      field.write(c);
      i++;
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    endRow();
  }
  return rows;
}

class _TooLarge implements Exception {
  _TooLarge(this.size);
  final int size;
}
