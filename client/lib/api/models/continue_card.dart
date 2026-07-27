class ContinueCard {
  ContinueCard({
    required this.kind,
    required this.id,
    required this.title,
    required this.cover,
    required this.lastPlayedAt,
    required this.playCount,
  });

  factory ContinueCard.fromJson(Map<String, dynamic> j) => ContinueCard(
        kind: j['kind'] as String,
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        cover: j['cover'] as String? ?? '',
        lastPlayedAt: DateTime.parse(j['lastPlayedAt'] as String),
        playCount: (j['playCount'] as num?)?.toInt() ?? 0,
      );

  final String kind; // "playlist" | "channel"
  final String id;
  final String title;
  final String cover;
  final DateTime lastPlayedAt;
  final int playCount;
}
