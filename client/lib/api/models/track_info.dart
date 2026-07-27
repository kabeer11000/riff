import 'format_info.dart';

class TrackInfo {
  TrackInfo({
    required this.id,
    required this.title,
    required this.uploader,
    required this.channelId,
    required this.duration,
    required this.thumbnail,
    required this.formats,
  });

  factory TrackInfo.fromJson(Map<String, dynamic> j) => TrackInfo(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        uploader: j['uploader'] as String? ?? '',
        channelId: j['channelId'] as String? ?? '',
        duration: (j['duration'] as num?)?.toDouble() ?? 0,
        thumbnail: j['thumbnail'] as String? ?? '',
        formats: ((j['formats'] as List?) ?? const [])
            .map((e) => FormatInfo.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final String title;
  final String uploader;
  final String channelId;
  final double duration;
  final String thumbnail;
  final List<FormatInfo> formats;

  /// Best audio format by ABR. The backend picks a directly-proxyable format
  /// with the highest bitrate; we mirror that on the client as a sanity check.
  FormatInfo? get bestAudio {
    FormatInfo? best;
    for (final f in formats) {
      if (!f.isAudio) continue;
      if (best == null || f.abr > best.abr) best = f;
    }
    return best;
  }
}