/// A minted R1 one-time share link: mirrors the agent's
/// `POST /v1/share/mint` response (and `GET /v1/share` list entries, which
/// omit [token] — it's only ever shown once).
class ShareLink {
  const ShareLink({
    this.token = '',
    required this.tokenHash,
    required this.path,
    required this.expiresAt,
    this.url = '',
  });

  /// The raw token. Only present in the mint response — never returned by
  /// GET /v1/share (the agent only stores the hash).
  final String token;
  final String tokenHash;

  /// Empty for entries from GET /v1/share/mint (the mint response doesn't
  /// echo the path); populated for entries from GET /v1/share.
  final String path;

  /// Unix seconds.
  final int expiresAt;

  /// Fully-qualified share URL. Empty for GET /v1/share list entries.
  final String url;

  DateTime get expiresAtDateTime =>
      DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);

  factory ShareLink.fromJson(Map<String, dynamic> json) => ShareLink(
    token: json['token'] as String? ?? '',
    tokenHash: json['tokenHash'] as String? ?? '',
    path: json['path'] as String? ?? '',
    expiresAt: json['expiresAt'] as int? ?? 0,
    url: json['url'] as String? ?? '',
  );
}
