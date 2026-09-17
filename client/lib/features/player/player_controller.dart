import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../../api/endpoints/history.dart';
import '../../api/endpoints/items.dart';
import '../../api/models/item.dart';
import '../../api/models/search_result.dart';
import '../../core/native_ytdl.dart';
import '../../core/url_state.dart';
import 'queue_provider.dart';

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
    this.item,
    this.isLoading = false,
    this.isPlaying = false,
    this.error,
  });

  // Display shape lifted from search/listings; track is what the player shows.
  final SearchResult? track;
  // Canonical record fetched on play(); carries sources[] for the embed and
  // any future provider-agnostic UI bits.
  final Item? item;
  final bool isLoading;
  final bool isPlaying;
  final Object? error;

  PlayerState copyWith({
    SearchResult? track,
    Item? item,
    bool? isLoading,
    bool? isPlaying,
    Object? error,
    bool clearError = false,
    bool clearTrack = false,
    bool clearItem = false,
  }) => PlayerState(
    track: clearTrack ? null : (track ?? this.track),
    item: clearItem ? null : (item ?? this.item),
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
  // Guards auto-advance: just_audio can report `completed` on more than one
  // stream event, and we only want one queue advance per loaded source.
  bool _completedFired = false;
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
    _sub = _player.playerStateStream.listen((ps) {
      final wasPlaying = state.isPlaying;
      final nowPlaying =
          ps.playing && ps.processingState != ja.ProcessingState.completed;
      state = state.copyWith(isPlaying: nowPlaying);
      if (wasPlaying && !nowPlaying) _onPauseOrStop();
      if (ps.processingState == ja.ProcessingState.completed &&
          !_completedFired) {
        _completedFired = true;
        ref.read(playbackQueueProvider.notifier).advance();
      }
    });
    ref.onDispose(() {
      _sub?.cancel();
      _historyTimer?.cancel();
    });
    return const PlayerState();
  }

  /// [contextKind] is one of "search" | "playlist" | "channel" | "library".
  Future<void> play(
    SearchResult track, {
    String contextKind = 'search',
    String contextId = '',
    String contextTitle = '',
    bool autoStart = true,
  }) async {
    final requestId = ++_playRequestId;
    _completedFired = false;
    _cancelHistory();
    _contextKind = contextKind;
    _contextId = contextId;
    _contextTitle = contextTitle;
    state = state.copyWith(
      track: track,
      isLoading: true,
      clearError: true,
      clearItem: true,
    );
    syncPlayerUrl(itemId: track.id);
    unawaited(_player.stop());
    final previous = _audioChain;
    final completer = Completer<void>();
    _audioChain = completer.future;
    try {
      await previous;
      if (requestId != _playRequestId) return;
      // Fetch canonical Item for the embed (sources[]) denormalized fields,
      // and to validate that the item still exists.
      final api = ref.read(itemsApiProvider);
      final item = await api.get(track.id);
      if (requestId != _playRequestId) return;

      // On platforms that can run a bundled yt-dlp (Windows today), resolve
      // locally: the same machine that resolves the stream URL also plays
      // it, so there's no datacenter-IP flagging and no IP-lock mismatch —
      // both problems the backend hits on Render. Falls back to the
      // backend's stream endpoint on any failure (video ID missing, native
      // resolve failed, non-Windows platform).
      String? url;
      final ytId = item.youtubeSource?.externalId;
      if (NativeYtdl.isSupported && ytId != null && ytId.isNotEmpty) {
        url = await NativeYtdl.resolveAudioUrl(ytId);
      }
      if (requestId != _playRequestId) return;
      url ??= api.streamUrl(track.id, kind: 'audio');
      await _player.setAudioSource(
        ja.AudioSource.uri(
          Uri.parse(url),
          tag: MediaItem(
            id: track.id,
            title: track.title,
            artist: track.uploader,
            artUri: track.thumbnail.isEmpty ? null : Uri.parse(track.thumbnail),
          ),
        ),
      );
      if (requestId != _playRequestId) return;
      state = state.copyWith(item: item, isLoading: false);
      if (autoStart) {
        unawaited(_player.play());
        _recordPlay(position: 0);
        _startHistoryTimer();
      }
    } catch (e) {
      if (requestId != _playRequestId) return;
      state = state.copyWith(isLoading: false, error: e, clearItem: true);
    } finally {
      completer.complete();
    }
  }

  /// Load a track by id alone, paused. Used to restore `?v=<itemId>` on a
  /// cold load, where all we have is the id — ItemsApi.get fills in the rest.
  Future<void> playById(String itemId) async {
    try {
      final item = await ref.read(itemsApiProvider).get(itemId);
      final uploader = item.artists.isEmpty ? '' : item.artists.first;
      await play(
        SearchResult(
          id: item.id,
          title: item.title,
          uploader: uploader,
          duration: item.duration,
          thumbnail: item.thumbnail,
          type: item.duration >= 600 ? 'video' : 'audio',
        ),
        autoStart: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e);
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
  }

  Future<void> stop() async {
    _recordFinalPosition();
    _cancelHistory();
    syncPlayerUrl();
    await _player.stop();
    state = state.copyWith(
      track: null,
      clearTrack: true,
      item: null,
      clearItem: true,
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
    unawaited(
      ref
          .read(historyApiProvider)
          .record(
            itemId: track.id,
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
