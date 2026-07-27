import 'package:flutter/widgets.dart';

import '../../api/models/item.dart';

/// Non-web placeholder for [YouTubeEmbed]. Renders nothing — the cover tab
/// remains the only option on platforms where we don't embed iframes. Items
/// without a YouTube source also render nothing.
class YouTubeEmbed extends StatelessWidget {
  const YouTubeEmbed({
    super.key,
    required this.item,
    this.aspectRatio = 16 / 9,
    this.showTheater = false,
    this.fullscreen = false,
  });

  final Item item;
  final double aspectRatio;
  final bool showTheater;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
