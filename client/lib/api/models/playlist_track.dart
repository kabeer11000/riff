/// Denormalized wire shape of one track inside a playlist. Mirrors the
/// server's domain.PlaylistTrack; carries enough metadata to render a tile
/// without a second fetch.
class PlaylistTrack {
  PlaylistTrack({
    required this.itemId,
    required this.position,
    required this.title,
    required this.uploader,
    required this.duration,
    required this.thumbnail,
    required this.addedAt,
  });

  factory PlaylistTrack.fromJson(Map<String, dynamic> j) => PlaylistTrack(
    itemId: j['itemId'] as String,
    position: (j['position'] as num?)?.toInt() ?? 0,
    title: j['title'] as String? ?? '',
    uploader: j['uploader'] as String? ?? '',
    duration: (j['duration'] as num?)?.toDouble() ?? 0,
    thumbnail: j['thumbnail'] as String? ?? '',
    addedAt: DateTime.parse(j['addedAt'] as String),
  );

  final String itemId;
  final int position;
  final String title;
  final String uploader;
  final double duration;
  final String thumbnail;
  final DateTime addedAt;
}
