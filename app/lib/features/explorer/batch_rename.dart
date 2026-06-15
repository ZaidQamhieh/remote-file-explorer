/// Pure helpers for batch-renaming a multi-selection (Wave 4 / G5).
///
/// Two modes:
///  - [BatchRenameMode.pattern]: give a base name; each item becomes
///    `base N` with a sequential, zero-padded number (or, if the base contains
///    the `{n}` placeholder, the number is substituted there). The original
///    file extension is preserved.
///  - [BatchRenameMode.findReplace]: replace every occurrence of `find` with
///    `replace` in each name (the whole name, extension included).
library;

enum BatchRenameMode { pattern, findReplace }

const _numberPlaceholder = '{n}';

/// Splits [name] into (stem, ext) where ext includes the leading dot. A leading
/// dot (dotfile like `.bashrc`) or a trailing dot is treated as part of the
/// stem, matching the rest of the app's extension handling.
({String stem, String ext}) splitNameExt(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return (stem: name, ext: '');
  return (stem: name.substring(0, dot), ext: name.substring(dot));
}

/// Computes the new file names for [names] (basenames, in order).
///
/// Returns a list the same length/order as [names]. Pattern numbering is
/// zero-padded to the width of the largest index so the renamed files sort
/// naturally (e.g. `Trip 01`..`Trip 12`). In find/replace mode an empty [find]
/// leaves names unchanged.
List<String> computeBatchRenames({
  required List<String> names,
  required BatchRenameMode mode,
  String base = '',
  int startNumber = 1,
  String find = '',
  String replace = '',
}) {
  switch (mode) {
    case BatchRenameMode.findReplace:
      if (find.isEmpty) return List<String>.from(names);
      return names.map((n) => n.replaceAll(find, replace)).toList();

    case BatchRenameMode.pattern:
      final last = startNumber + names.length - 1;
      final width = last.toString().length;
      final out = <String>[];
      for (var i = 0; i < names.length; i++) {
        final number = (startNumber + i).toString().padLeft(width, '0');
        final ext = splitNameExt(names[i]).ext;
        final stem =
            base.contains(_numberPlaceholder)
                ? base.replaceAll(_numberPlaceholder, number)
                : '${base.isEmpty ? 'file' : base} $number';
        out.add('$stem$ext');
      }
      return out;
  }
}
