import 'package:flutter/widgets.dart';

/// Non-web placeholder for [YouTubeEmbed]. Renders nothing — the cover tab
/// remains the only option on platforms where we don't embed YouTube iframes.
class YouTubeEmbed extends StatelessWidget {
  const YouTubeEmbed({
    super.key,
    required this.videoId,
    this.aspectRatio = 16 / 9,
    this.showTheater = false,
    this.fullscreen = false,
  });

  final String videoId;
  final double aspectRatio;
  final bool showTheater;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
