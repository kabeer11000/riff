class SearchResult {
  SearchResult({
    required this.id,
    required this.title,
    required this.uploader,
    required this.duration,
    required this.thumbnail,
    required this.type,
  });

  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        uploader: j['uploader'] as String? ?? '',
        duration: (j['duration'] as num?)?.toDouble() ?? 0,
        thumbnail: j['thumbnail'] as String? ?? '',
        type: j['type'] as String? ?? 'video',
      );

  final String id;
  final String title;
  final String uploader;
  final double duration;
  final String thumbnail;
  final String type;
}