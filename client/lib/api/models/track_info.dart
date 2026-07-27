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
    this.description = '',
    this.artist = '',
    this.album = '',
    this.uploadDate = '',
    this.viewCount = 0,
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
        description: j['description'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        album: j['album'] as String? ?? '',
        uploadDate: j['uploadDate'] as String? ?? '',
        viewCount: (j['viewCount'] as num?)?.toDouble() ?? 0,
      );

  final String id;
  final String title;
  final String uploader;
  final String channelId;
  final double duration;
  final String thumbnail;
  final List<FormatInfo> formats;
  final String description;
  final String artist;
  final String album;
  /// YYYYMMDD or '' if unknown.
  final String uploadDate;
  final double viewCount;

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

  /// Release year parsed from [uploadDate] (YYYYMMDD). Null when unparseable.
  int? get releaseYear {
    if (uploadDate.length < 4) return null;
    return int.tryParse(uploadDate.substring(0, 4));
  }
}
