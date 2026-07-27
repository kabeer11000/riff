import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/search_result.dart';
import 'player_controller.dart';

/// The playback queue plus a cursor pointing at the track that's currently
/// loaded in the player. Everything before [index] is history, everything
/// after is up next. In-memory only; the browser URL (`?v=`) is what
/// survives a refresh.
class QueueState {
  const QueueState({this.tracks = const [], this.index = -1});

  final List<SearchResult> tracks;

  /// Index into [tracks] of the loaded track. -1 when the queue is empty.
  final int index;

  SearchResult? get current =>
      (index >= 0 && index < tracks.length) ? tracks[index] : null;
  bool get hasNext => index >= 0 && index < tracks.length - 1;
  bool get hasPrevious => index > 0;
  bool get isEmpty => tracks.isEmpty;

  QueueState copyWith({List<SearchResult>? tracks, int? index}) => QueueState(
    tracks: tracks ?? this.tracks,
    index: index ?? this.index,
  );
}

final playbackQueueProvider =
    NotifierProvider<PlaybackQueue, QueueState>(PlaybackQueue.new);

/// Owns track selection. [PlayerController] stays the audio loader: every
/// cursor move here ends in a `player.play(...)` call. History context is
/// held per-queue so all tracks from one source record the same context.
class PlaybackQueue extends Notifier<QueueState> {
  String _contextKind = 'search';
  String _contextId = '';
  String _contextTitle = '';

  @override
  QueueState build() => const QueueState();

  /// Replace the queue with [tracks] and start playing [index].
  void playFrom(
    List<SearchResult> tracks,
    int index, {
    String contextKind = 'search',
    String contextId = '',
    String contextTitle = '',
  }) {
    if (tracks.isEmpty || index < 0 || index >= tracks.length) return;
    _contextKind = contextKind;
    _contextId = contextId;
    _contextTitle = contextTitle;
    state = QueueState(tracks: List.of(tracks), index: index);
    _play();
  }

  /// Play the track at [index] (queue panel row tap).
  void jumpTo(int index) {
    if (index < 0 || index >= state.tracks.length || index == state.index) {
      return;
    }
    state = state.copyWith(index: index);
    _play();
  }

  void next() {
    if (!state.hasNext) return;
    state = state.copyWith(index: state.index + 1);
    _play();
  }

  void previous() {
    if (!state.hasPrevious) return;
    state = state.copyWith(index: state.index - 1);
    _play();
  }

  /// Called when a track finishes. Stops at the end of the queue — the audio
  /// backend has already stopped, so there's nothing to do.
  void advance() => next();

  /// Append [track]. Starts playback when the queue was empty, so
  /// "Add to queue" on a cold player does the obvious thing.
  void addToQueue(SearchResult track) {
    final wasEmpty = state.isEmpty;
    state = QueueState(
      tracks: [...state.tracks, track],
      index: wasEmpty ? 0 : state.index,
    );
    if (wasEmpty) _play();
  }

  /// Insert [track] directly after the current one.
  void playNext(SearchResult track) {
    if (state.isEmpty) {
      addToQueue(track);
      return;
    }
    final tracks = [...state.tracks]..insert(state.index + 1, track);
    state = state.copyWith(tracks: tracks);
  }

  /// Remove the entry at [index], keeping the cursor on whatever is playing.
  /// Removing the current track advances to the next one (or stops the
  /// player when it was the last).
  void removeAt(int index) {
    if (index < 0 || index >= state.tracks.length) return;
    final tracks = [...state.tracks]..removeAt(index);
    final wasCurrent = index == state.index;
    var cursor = state.index;
    if (index < state.index) cursor -= 1;
    if (tracks.isEmpty) {
      state = const QueueState();
      ref.read(playerControllerProvider.notifier).stop();
      return;
    }
    if (wasCurrent && cursor >= tracks.length) cursor = tracks.length - 1;
    state = QueueState(tracks: tracks, index: cursor);
    if (wasCurrent) _play();
  }

  /// [ReorderableListView] semantics: [newIndex] is the slot the row lands in
  /// before the old one is removed. The cursor follows the playing track.
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.tracks.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= state.tracks.length) return;
    if (newIndex == oldIndex) return;
    final tracks = [...state.tracks];
    final moved = tracks.removeAt(oldIndex);
    tracks.insert(newIndex, moved);
    var cursor = state.index;
    if (oldIndex == cursor) {
      cursor = newIndex;
    } else if (oldIndex < cursor && newIndex >= cursor) {
      cursor -= 1;
    } else if (oldIndex > cursor && newIndex <= cursor) {
      cursor += 1;
    }
    state = QueueState(tracks: tracks, index: cursor);
  }

  /// Drop everything up next, keeping the current track loaded so clearing
  /// the queue doesn't cut the music off mid-song.
  void clear() {
    final track = state.current;
    if (track == null) {
      state = const QueueState();
      return;
    }
    state = QueueState(tracks: [track], index: 0);
  }

  void _play() {
    final track = state.current;
    if (track == null) return;
    ref
        .read(playerControllerProvider.notifier)
        .play(
          track,
          contextKind: _contextKind,
          contextId: _contextId,
          contextTitle: _contextTitle,
        );
  }
}
