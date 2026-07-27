class HistoryEntry {
  HistoryEntry({
    required this.videoId,
    required this.title,
    required this.uploader,
    required this.duration,
    required this.thumbnail,
    required this.lastPlayedAt,
    required this.playCount,
    required this.lastPosition,
    required this.isLongForm,
    required this.contextKind,
    required this.contextId,
    required this.contextTitle,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        videoId: j['videoId'] as String,
        title: j['title'] as String? ?? '',
        uploader: j['uploader'] as String? ?? '',
        duration: (j['duration'] as num?)?.toDouble() ?? 0,
        thumbnail: j['thumbnail'] as String? ?? '',
        lastPlayedAt: DateTime.parse(j['lastPlayedAt'] as String),
        playCount: (j['playCount'] as num?)?.toInt() ?? 0,
        lastPosition: (j['lastPosition'] as num?)?.toDouble() ?? 0,
        isLongForm: j['isLongForm'] as bool? ?? false,
        contextKind: j['contextKind'] as String? ?? '',
        contextId: j['contextId'] as String? ?? '',
        contextTitle: j['contextTitle'] as String? ?? '',
      );

  final String videoId;
  final String title;
  final String uploader;
  final double duration;
  final String thumbnail;
  final DateTime lastPlayedAt;
  final int playCount;
  final double lastPosition;
  final bool isLongForm;
  final String contextKind;
  final String contextId;
  final String contextTitle;
}
