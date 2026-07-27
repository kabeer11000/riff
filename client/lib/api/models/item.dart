/// Provider-agnostic canonical item. Multiple [Source]s may point at the same
/// item across different providers; the same YouTube video indexed once stays
/// unique to that item_id.
class Item {
  Item({
    required this.id,
    required this.title,
    required this.artists,
    required this.album,
    required this.duration,
    required this.thumbnail,
    required this.sources,
  });

  factory Item.fromJson(Map<String, dynamic> j) => Item(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    artists: ((j['artists'] as List?) ?? const [])
        .map((e) => e as String)
        .toList(),
    album: j['album'] as String? ?? '',
    duration: (j['duration'] as num?)?.toDouble() ?? 0,
    thumbnail: j['thumbnail'] as String? ?? '',
    sources: ((j['sources'] as List?) ?? const [])
        .map((e) => Source.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String title;
  final List<String> artists;
  final String album;
  final double duration;
  final String thumbnail;
  final List<Source> sources;

  /// First YouTube source, or null if this item isn't on YouTube.
  Source? get youtubeSource {
    for (final s in sources) {
      if (s.provider == 'youtube') return s;
    }
    return null;
  }

  bool get hasYoutube => youtubeSource != null;
}

class Source {
  Source({
    required this.provider,
    required this.externalId,
    required this.url,
    this.metadata,
  });

  factory Source.fromJson(Map<String, dynamic> j) => Source(
    provider: j['provider'] as String? ?? '',
    externalId: j['externalId'] as String? ?? '',
    url: j['url'] as String? ?? '',
    metadata: j['metadata'] is Map<String, dynamic>
        ? j['metadata'] as Map<String, dynamic>
        : null,
  );

  final String provider;
  final String externalId;
  final String url;

  /// Per-provider free-form metadata. Keys depend on the source's provider;
  /// the player UI renders known fields via a per-provider schema and falls
  /// back to key/value rows for anything else.
  final Map<String, dynamic>? metadata;
}
