import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/search_result.dart';

/// In-memory queue of tracks appended from the context menu's "Add to
/// queue" / "Play next" actions. The player doesn't consume this yet —
/// the queue is stored so future auto-advance + queue UI can read it
/// without re-architecting context-menu storage. In-memory only; resets
/// on app restart. Persist when the queue UI lands.
class PlaybackQueue extends Notifier<List<SearchResult>> {
  @override
  List<SearchResult> build() => const [];

  /// Append [track] to the end of the queue.
  void addToQueue(SearchResult track) {
    state = [...state, track];
  }

  /// Insert [track] at the front so it plays as soon as the current
  /// track finishes.
  void playNext(SearchResult track) {
    state = [track, ...state];
  }

  void removeAt(int index) {
    if (index < 0 || index >= state.length) return;
    state = [...state]..removeAt(index);
  }

  void clear() {
    state = const [];
  }
}

final playbackQueueProvider =
    NotifierProvider<PlaybackQueue, List<SearchResult>>(PlaybackQueue.new);
