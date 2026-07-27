import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which surface the big player renders in its cover slot. Persists across
/// open/close of the player. [PlayerTab.video] is web-only — callers gate on
/// kIsWeb before offering it.
enum PlayerTab { cover, video, queue }

class PlayerTabNotifier extends Notifier<PlayerTab> {
  @override
  PlayerTab build() => PlayerTab.cover;

  void set(PlayerTab tab) => state = tab;
}

final playerTabProvider = NotifierProvider<PlayerTabNotifier, PlayerTab>(
  PlayerTabNotifier.new,
);

/// Derived so the theater-mode and disk-hiding checks scattered across
/// app.dart / big_player.dart keep reading a plain bool.
final videoTabEnabledProvider = Provider<bool>(
  (ref) => ref.watch(playerTabProvider) == PlayerTab.video,
);

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
