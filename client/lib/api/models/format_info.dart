class FormatInfo {
  FormatInfo({
    required this.formatId,
    required this.ext,
    required this.kind,
    required this.acodec,
    required this.vcodec,
    required this.abr,
    required this.height,
    required this.filesize,
  });

  factory FormatInfo.fromJson(Map<String, dynamic> j) => FormatInfo(
        formatId: j['formatId'] as String? ?? '',
        ext: j['ext'] as String? ?? '',
        kind: j['kind'] as String? ?? '',
        acodec: j['acodec'] as String? ?? '',
        vcodec: j['vcodec'] as String? ?? '',
        abr: (j['abr'] as num?)?.toDouble() ?? 0,
        height: (j['height'] as num?)?.toDouble() ?? 0,
        filesize: (j['filesize'] as num?)?.toDouble() ?? 0,
      );

  final String formatId;
  final String ext;
  final String kind; // "audio" | "muxed"
  final String acodec;
  final String vcodec;
  final double abr;
  final double height;
  final double filesize;

  bool get isAudio => kind == 'audio';
}