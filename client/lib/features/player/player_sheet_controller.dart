import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Snap states for the big-player sheet. `hidden` means the sheet is not
/// on screen (the miniplayer is the only player surface visible).
enum PlayerSheetMode { hidden, expanded, full }

class PlayerSheetState {
  const PlayerSheetState({this.mode = PlayerSheetMode.hidden});
  final PlayerSheetMode mode;
}

class PlayerSheetController extends Notifier<PlayerSheetState> {
  @override
  PlayerSheetState build() => const PlayerSheetState();

  void open() => state = const PlayerSheetState(mode: PlayerSheetMode.expanded);
  void expand() => state = const PlayerSheetState(mode: PlayerSheetMode.full);
  void collapse() =>
      state = const PlayerSheetState(mode: PlayerSheetMode.expanded);
  void close() => state = const PlayerSheetState();
}

final playerSheetControllerProvider =
    NotifierProvider<PlayerSheetController, PlayerSheetState>(
      PlayerSheetController.new,
    );
