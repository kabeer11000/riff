import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the YouTube embed is in Flutter-managed fullscreen. When true, the
/// app overlays a full-window embed on top of the main layout (see app.dart)
/// and suppresses the inline embed so we only have one iframe mounted.
class VideoFullscreen extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void set(bool v) => state = v;
}

final fullscreenVideoProvider = NotifierProvider<VideoFullscreen, bool>(
  VideoFullscreen.new,
);
