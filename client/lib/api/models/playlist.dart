class Playlist {
  Playlist({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.visibility,
  });

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        coverUrl: j['coverUrl'] as String? ?? '',
        visibility: j['visibility'] as String? ?? 'private',
      );

  final String id;
  final String name;
  final String coverUrl;
  final String visibility;
}