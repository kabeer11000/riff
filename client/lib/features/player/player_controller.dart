import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../../api/endpoints/history.dart';
import '../../api/endpoints/tracks.dart';
import '../../api/models/search_result.dart';
import '../search/search_controller.dart';

final tracksApiProvider = Provider<TracksApi>(
  (ref) => TracksApi(ref.watch(apiClientProvider)),
);

final audioPlayerProvider = Provider<ja.AudioPlayer>((ref) {
  final p = ja.AudioPlayer();
  ref.onDispose(p.dispose);
  return p;
});

const _longFormThresholdSec = 600.0;
const _historySyncInterval = Duration(seconds: 30);

class PlayerState {
  const PlayerState({
    this.track,
    this.description = '',
    this.isLoading = false,
    this.isPlaying = false,
    this.error,
  });

  final SearchResult? track;
  final String description;
  final bool isLoading;
  final bool isPlaying;
  final Object? error;

  PlayerState copyWith({
    SearchResult? track,
    String? description,
    bool? isLoading,
    bool? isPlaying,
    Object? error,
    bool clearError = false,
    bool clearTrack = false,
  }) => PlayerState(
    track: clearTrack ? null : (track ?? this.track),
    description: description ?? this.description,
    isLoading: isLoading ?? this.isLoading,
    isPlaying: isPlaying ?? this.isPlaying,
    error: clearError ? null : (error ?? this.error),
  );
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);

class PlayerController extends Notifier<PlayerState> {
  StreamSubscription<ja.PlayerState>? _sub;
  Timer? _historyTimer;
  // Monotonic id of the most recent play() call. Earlier in-flight calls
  // bail out at each await so a stale setUrl/play() can't overwrite the
  // player when a newer track has been requested.
  int _playRequestId = 0;
  // Single-flight chain: every play() awaits the previous one so the
  // underlying AudioPlayer never receives overlapping setUrl/stop calls.
  Future<void> _audioChain = Future.value();
  // Context for the currently-loaded track. Set on play(); used for the
  // initial POST and for the periodic sync until the next play().
  String _contextKind = '';
  String _contextId = '';
  String _contextTitle = '';

  ja.AudioPlayer get _player => ref.read(audioPlayerProvider);

  @override
  PlayerState build() {
    // isPlaying is driven by the player; isLoading is set explicitly by play()
    // because just_audio re-enters ProcessingState.buffering for every Range
    // request during playback, which would otherwise keep the spinner up.
    _sub = _player.playerStateStream.listen((ps) {
      final wasPlaying = state.isPlaying;
      // Track completion isn't always reflected by `playing` alone — force
      // not-playing when the audio backend reports the item as completed,
      // otherwise the disk keeps spinning past the end.
      final nowPlaying =
          ps.playing && ps.processingState != ja.ProcessingState.completed;
      state = state.copyWith(isPlaying: nowPlaying);
      if (wasPlaying && !nowPlaying) _onPauseOrStop();
    });
    ref.onDispose(() {
      _sub?.cancel();
      _historyTimer?.cancel();
    });
    return const PlayerState();
  }

  /// [contextKind] is one of "search" | "playlist" | "channel" | "library".
  /// Defaults to search; callers wire playlists/channels as those screens land.
  Future<void> play(
    SearchResult track, {
    String contextKind = 'search',
    String contextId = '',
    String contextTitle = '',
  }) async {
    final requestId = ++_playRequestId;
    _cancelHistory();
    _contextKind = contextKind;
    _contextId = contextId;
    _contextTitle = contextTitle;
    // State flips synchronously: the UI shows the new track + spinner and
    // (on mobile) the big player opens immediately.
    state = state.copyWith(track: track, isLoading: true, clearError: true);
    // Pause any in-flight playback so the previous track stops bleeding
    // through the gap before the new source is ready. Fire-and-forget so
    // the state update is visible on the same frame.
    unawaited(_player.stop());
    // Serialize the rest of the load against any earlier play() so just_audio
    // never sees overlapping setUrl calls.
    final previous = _audioChain;
    final completer = Completer<void>();
    _audioChain = completer.future;
    try {
      await previous;
      if (requestId != _playRequestId) return;
      final api = ref.read(tracksApiProvider);
      final info = await api.get(track.id);
      if (requestId != _playRequestId) return;
      if (info.bestAudio == null) {
        throw StateError('no audio format for ${track.id}');
      }
      final url = api.streamUrl(track.id, kind: 'audio');
      await _player.setUrl(url);
      if (requestId != _playRequestId) return;
      // Spinner off here: source is loaded and ready. Buffering state during
      // playback is normal and would re-trigger the spinner via the stream.
      state = state.copyWith(isLoading: false, description: info.description);
      unawaited(_player.play());
      _recordPlay(position: 0);
      _startHistoryTimer();
    } catch (e) {
      if (requestId != _playRequestId) return;
      state = state.copyWith(isLoading: false, error: e);
    } finally {
      completer.complete();
    }
  }

  Future<void> togglePlayPause() async {
    if (state.track == null) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      unawaited(_player.play());
      _recordPlay(position: _player.position.inMilliseconds / 1000.0);
    }
    // isPlaying flips via the stream listener.
  }

  Future<void> stop() async {
    _recordFinalPosition();
    _cancelHistory();
    await _player.stop();
    state = state.copyWith(
      track: null,
      isPlaying: false,
      isLoading: false,
      clearError: true,
    );
  }

  void _startHistoryTimer() {
    _historyTimer = Timer.periodic(_historySyncInterval, (_) {
      if (!state.isPlaying) return;
      if (!_isLongForm(state.track?.duration)) return;
      _recordPlay(position: _player.position.inMilliseconds / 1000.0);
    });
  }

  static bool _isLongForm(double? durationSec) =>
      (durationSec ?? 0) >= _longFormThresholdSec;

  void _onPauseOrStop() {
    _recordFinalPosition();
    _historyTimer?.cancel();
    _historyTimer = null;
  }

  void _cancelHistory() {
    _historyTimer?.cancel();
    _historyTimer = null;
  }

  void _recordFinalPosition() {
    final track = state.track;
    if (track == null) return;
    final pos = _player.position.inMilliseconds / 1000.0;
    _recordPlay(position: pos);
  }

  void _recordPlay({required double position}) {
    final track = state.track;
    if (track == null) return;
    // Fire and forget; HistoryApi failures are best-effort (lost tick is OK).
    unawaited(
      ref
          .read(historyApiProvider)
          .record(
            videoId: track.id,
            title: track.title,
            uploader: track.uploader,
            duration: track.duration,
            thumbnail: track.thumbnail,
            position: position,
            contextKind: _contextKind,
            contextId: _contextId,
            contextTitle: _contextTitle,
          ),
    );
  }
}
