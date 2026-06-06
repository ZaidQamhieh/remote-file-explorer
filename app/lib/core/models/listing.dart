import 'entry.dart';

/// A paginated directory listing returned by `GET /fs`.
class Listing {
  const Listing({
    required this.path,
    required this.entries,
    this.nextCursor,
  });

  final String path;
  final List<Entry> entries;

  /// Opaque cursor for the next page; null when no more pages.
  final String? nextCursor;

  factory Listing.fromJson(Map<String, dynamic> json) => Listing(
        path: json['path'] as String? ?? '',
        entries: (json['entries'] as List<dynamic>? ?? [])
            .map((e) => Entry.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextCursor: json['nextCursor'] as String?,
      );
}
