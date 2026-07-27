import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riff/api/models/search_result.dart';
import 'package:riff/features/player/player_controller.dart';
import 'package:riff/features/player/queue_provider.dart';

/// Stubs the player controller so the queue can call play() without booting
/// just_audio. Records every play() call in order so tests can assert the
/// sequence of loaded tracks.
class _FakePlayer extends PlayerController {
  final List<SearchResult> plays = [];

  @override
  PlayerState build() => const PlayerState();

  @override
  Future<void> play(
    SearchResult track, {
    String contextKind = 'search',
    String contextId = '',
    String contextTitle = '',
    bool autoStart = true,
  }) async {
    plays.add(track);
    state = state.copyWith(track: track);
  }

  @override
  Future<void> stop() async {
    state = const PlayerState();
  }
}

SearchResult _track(String id) => SearchResult(
  id: id,
  title: 'T-$id',
  uploader: 'U',
  duration: 0,
  thumbnail: '',
  type: 'audio',
);

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(_FakePlayer.new),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('playFrom sets the queue and plays the chosen index', () {
    final queue = container.read(playbackQueueProvider.notifier);
    queue.playFrom([_track('a'), _track('b'), _track('c')], 1);
    final s = container.read(playbackQueueProvider);
    expect(s.tracks.map((t) => t.id), ['a', 'b', 'c']);
    expect(s.index, 1);
    final player = container.read(playerControllerProvider.notifier) as _FakePlayer;
    expect(player.plays.map((t) => t.id), ['b']);
  });

  test('next() advances; past the end is a no-op', () {
    final queue = container.read(playbackQueueProvider.notifier);
    queue.playFrom([_track('a'), _track('b')], 0);
    final player = container.read(playerControllerProvider.notifier) as _FakePlayer;
    queue.next();
    expect(container.read(playbackQueueProvider).index, 1);
    expect(player.plays.last.id, 'b');
    queue.next();
    expect(container.read(playbackQueueProvider).index, 1, reason: 'no-op');
    expect(player.plays.length, 2, reason: 'no extra play()');
  });

  test('previous() rewinds; before 0 is a no-op', () {
    final queue = container.read(playbackQueueProvider.notifier);
    queue.playFrom([_track('a'), _track('b')], 1);
    final player = container.read(playerControllerProvider.notifier) as _FakePlayer;
    queue.previous();
    expect(container.read(playbackQueueProvider).index, 0);
    expect(player.plays.last.id, 'a');
    queue.previous();
    expect(container.read(playbackQueueProvider).index, 0, reason: 'no-op');
  });

  test('advance() delegates to next() and stops at the queue end', () {
    final queue = container.read(playbackQueueProvider.notifier);
    queue.playFrom([_track('a')], 0);
    final player = container.read(playerControllerProvider.notifier) as _FakePlayer;
    queue.advance();
    expect(container.read(playbackQueueProvider).index, 0, reason: 'no next');
    expect(player.plays.length, 1, reason: 'no extra play()');
  });

  test('playNext inserts directly after the current track', () {
    final queue = container.read(playbackQueueProvider.notifier);
    queue.playFrom([_track('a'), _track('b')], 0);
    queue.playNext(_track('z'));
    expect(
      container.read(playbackQueueProvider).tracks.map((t) => t.id),
      ['a', 'z', 'b'],
    );
    expect(container.read(playbackQueueProvider).index, 0);
  });

  test('addToQueue appends; playing the first starts playback', () {
    final queue = container.read(playbackQueueProvider.notifier);
    queue.addToQueue(_track('a'));
    queue.addToQueue(_track('b'));
    final s = container.read(playbackQueueProvider);
    expect(s.tracks.map((t) => t.id), ['a', 'b']);
    expect(s.index, 0);
    final player = container.read(playerControllerProvider.notifier) as _FakePlayer;
    expect(player.plays.map((t) => t.id), ['a']);
  });

  test('removeAt before cursor decrements the cursor', () {
    final queue = container.read(playbackQueueProvider.notifier);
    queue.playFrom([_track('a'), _track('b'), _track('c')], 2);
    queue.removeAt(0);
    final s = container.read(playbackQueueProvider);
    expect(s.tracks.map((t) => t.id), ['b', 'c']);
    expect(s.index, 1, reason: 'still on c');
  });

  test('removeAt the current track advances to the next and plays it', () {
    final queue = container.read(playbackQueueProvider.notifier);
    queue.playFrom([_track('a'), _track('b'), _track('c')], 1);
    final player = container.read(playerControllerProvider.notifier) as _FakePlayer;
    final playsBefore = player.plays.length;
    queue.removeAt(1);
    final s = container.read(playbackQueueProvider);
    expect(s.tracks.map((t) => t.id), ['a', 'c']);
    expect(s.index, 1);
    expect(player.plays.length, playsBefore + 1);
    expect(player.plays.last.id, 'c');
  });

  test('removeAt the last remaining track stops the player', () {
    final queue = container.read(playbackQueueProvider.notifier);
    queue.playFrom([_track('a')], 0);
    final player = container.read(playerControllerProvider.notifier) as _FakePlayer;
    queue.removeAt(0);
    expect(container.read(playbackQueueProvider).isEmpty, isTrue);
    expect(player.plays.last.id, 'a', reason: 'no new play after stop');
  });

  test('reorder keeps the cursor on the currently playing track', () {
    final queue = container.read(playbackQueueProvider.notifier);
    queue.playFrom(
      [_track('a'), _track('b'), _track('c'), _track('d')],
      1,
    );
    // Move 'b' (index 1) to position 3 (newIndex 4 pre-shift, 3 post-shift).
    queue.reorder(1, 4);
    final s = container.read(playbackQueueProvider);
    expect(s.tracks.map((t) => t.id), ['a', 'c', 'd', 'b']);
    expect(s.index, 3, reason: 'cursor follows the playing track');
  });

  test('clear() keeps the current track loaded', () {
    final queue = container.read(playbackQueueProvider.notifier);
    queue.playFrom([_track('a'), _track('b'), _track('c')], 1);
    final player = container.read(playerControllerProvider.notifier) as _FakePlayer;
    final playsBefore = player.plays.length;
    queue.clear();
    final s = container.read(playbackQueueProvider);
    expect(s.tracks.map((t) => t.id), ['b']);
    expect(s.index, 0);
    expect(player.plays.length, playsBefore, reason: 'clear() never replays');
  });
}
