import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the big player is rendering the YouTube video tab instead of the
/// cover image. Persists across open/close of the player.
class VideoTab extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final videoTabEnabledProvider = NotifierProvider<VideoTab, bool>(VideoTab.new);

/// Theater mode: on desktop, widens the big-player sidebar and hides the
/// library so the video fills the screen. Only meaningful while the video tab
/// is active on a wide/desktop layout.
class TheaterMode extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final theaterModeProvider = NotifierProvider<TheaterMode, bool>(
  TheaterMode.new,
);
