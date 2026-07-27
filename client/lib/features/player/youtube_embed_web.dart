import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui' show ImageFilter;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import 'ambient_lighting_provider.dart';
import 'music_disk.dart';
import 'player_controller.dart';
import 'video_fullscreen_provider.dart';
import 'video_tab_provider.dart';

const _seekStepSec = 10.0;
const _loadGrace = Duration(seconds: 2);
const _seekQuietZone = Duration(milliseconds: 600);
const _driftThreshold = 1.5;
const _viewType = 'riff-youtube-embed';
// Matches the panel radius so the video reads as a card, not a hard rectangle.
const _embedRadius = 16.0;

/// Web-only widget that embeds a muted YouTube iframe and keeps it in sync
/// with the just_audio player. The iframe is purely visual — audio plays
/// through just_audio and we push our state to YouTube via postMessage.
///
/// Fullscreen handling: tapping the fullscreen button flips
/// [fullscreenVideoProvider]. The app's root shell observes it and overlays a
/// separate, full-window embed; we don't use the iframe's native fullscreen
/// API because it would hide our Flutter controls. We also escape via Esc.
class YouTubeEmbed extends ConsumerStatefulWidget {
  const YouTubeEmbed({
    super.key,
    required this.videoId,
    this.aspectRatio = 16 / 9,
    this.showTheater = false,
    this.fullscreen = false,
  });

  final String videoId;
  final double aspectRatio;
  // Show the theater-mode toggle next to fullscreen. Only the desktop sidebar
  // surface passes true — theater mode has no meaning in the mobile sheet.
  final bool showTheater;

  // True on the full-window overlay variant. Suppresses double-tap-to-seek
  // (we already own the whole viewport) and renders a "close fullscreen"
  // button in place of the regular fullscreen button.
  final bool fullscreen;

  @override
  ConsumerState<YouTubeEmbed> createState() => _YouTubeEmbedState();
}

class _YouTubeEmbedState extends ConsumerState<YouTubeEmbed> {
  static const _hideControlsAfter = Duration(milliseconds: 2500);
  static final _iframe = web.HTMLIFrameElement()
    ..style.border = 'none'
    ..style.width = '100%'
    ..style.height = '100%'
    // Swallow all pointer input so YouTube's own chrome (title, share, context
    // menu) can never be triggered. Our own fullscreen button sits on top.
    ..style.setProperty('pointer-events', 'none')
    ..allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen';
  // registerViewFactory throws on duplicate names, so we only register once
  // across the app lifetime even though initState may fire multiple times
  // (inline ↔ fullscreen toggle).
  static bool _factoryRegistered = false;
  // Monotonic counter bumped on every YouTubeEmbed mount. Stored on the
  // shared iframe element via a JS-side custom property so commands from a
  // previous mount can detect they're stale when their State disposes mid
  // listener-fire. Without this guard, an old embed's queued pauseVideo
  // can race past the new embed's playVideo and leave the iframe sitting
  // on the red thumbnail while audio keeps playing.
  static int _mountCounter = 0;

  // Tracks which videoId the iframe is currently configured for.
  String? _currentVideoId;
  // Anchor for estimating where the video should be: the audio position and
  // wall-clock time at our last seek. Expected video position while playing =
  // _anchorSecs + elapsed wall time since _anchorWall.
  double _anchorSecs = 0;
  DateTime _anchorWall = DateTime.now();
  bool _videoPlaying = false;
  // Subscriptions torn down in dispose.
  StreamSubscription<Duration>? _positionSub;
  ProviderSubscription<PlayerState>? _stateSub;
  // Epoch this State was mounted under. Stored on the shared iframe element
  // when we load a video; commands from prior mounts become no-ops once the
  // iframe's epoch has moved on (e.g. inline → fullscreen swap).
  late final int _mountEpoch;
  // Flip in dispose so any in-flight async commands from this State are
  // dropped before they reach the iframe.
  bool _disposed = false;

  // Auto-hide overlay controls (YouTube-style). True = visible. The overlay
  // also stays visible while the user is scrubbing or holding a button.
  bool _controlsVisible = true;
  Timer? _hideTimer;

  // Watchdog: if audio is playing but YT's iframe has dropped to the paused-
  // on-thumbnail state (which can happen across fullscreen / theater mode
  // toggles), the listener-driven playVideo may not land reliably. Re-issue
  // playVideo on a short interval while audio is playing. The iframe ignores
  // it when already playing, so the cost is one postMessage per second.
  Timer? _playWatchdog;

  // Sync-rate limiting. After a fresh load or a seek we ignore drift for a
  // window — without it, position-stream transients (old values around the
  // seek) cause spurious re-seeks that visibly re-buffer the iframe.
  DateTime _suppressDriftUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    // Register the factory once across the app lifetime — Flutter throws if
    // we re-register under the same viewType. The iframe element is static
    // so all HtmlElementView instances share the same DOM node; we just
    // rewrite its src when videoId changes.
    if (!_factoryRegistered) {
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int viewId) => _iframe,
      );
      _factoryRegistered = true;
    }
    // Claim ownership of the shared iframe for this State's lifetime. Any
    // postMessage from a prior mount becomes a no-op once the iframe's epoch
    // moves past theirs. We set the dataset up front so the very first
    // command from this listener (or a follow-up state change) passes the
    // gate immediately — without this, the first _postCommand would race
    // against _loadVideo and silently drop.
    _mountEpoch = ++_mountCounter;
    _iframe.dataset['mountEpoch'] = _mountEpoch.toString();

    _stateSub = ref.listenManual<PlayerState>(playerControllerProvider, (
      prev,
      next,
    ) {
      // Track id change: swap the iframe to the new video once audio is
      // actually playing it. Loading the iframe while audio is still
      // fetching the source lets the iframe drift ahead — by the time audio
      // reaches 0 the iframe can already be at 0.5–1s due to muted autoplay
      // in the URL.
      final prevId = prev?.track?.id;
      final nextId = next.track?.id;
      final wasPlaying = prev?.isPlaying ?? false;
      final isPlaying = next.isPlaying;

      if (nextId != null && nextId != prevId && isPlaying) {
        _loadVideo(nextId, autoplay: true);
      } else if (nextId != null && nextId != prevId) {
        // Track switched but not yet playing: load the iframe paused-at-0
        // (autoplay=0 in URL) so it shows the thumbnail and doesn't race
        // ahead. When audio finally plays we'll send playVideo + seekTo to
        // start it cleanly.
        _loadVideo(nextId, autoplay: false);
      }

      // Play/pause transitions.
      if (isPlaying != wasPlaying) {
        if (isPlaying) {
          // Re-anchor the iframe onto the audio's exact current position
          // before issuing playVideo. Without this the iframe resumes from
          // wherever wall-clock says it should be, which can be off by
          // hundreds of ms from where audio actually is.
          final pos = ref.read(audioPlayerProvider).position.inMilliseconds /
              1000.0;
          if (pos > 0) _postSeek(pos);
          _postCommand('playVideo');
          _setPlaying(true);
          // Belt and braces: re-issue playVideo after YT's API has had a
          // moment to attach. Without this, a playVideo that races ahead of
          // the iframe's API-ready event silently fails and the iframe sits
          // on the thumbnail while audio plays.
          Future<void>.delayed(const Duration(milliseconds: 600), () {
            if (!mounted || _disposed) return;
            if (ref.read(playerControllerProvider).isPlaying) {
              _postCommand('playVideo');
            }
          });
          // Long-running watchdog: re-assert playVideo periodically while
          // audio is playing. Catches the case where the iframe silently
          // drops to a paused-on-thumbnail state after a mode toggle.
          _playWatchdog?.cancel();
          _playWatchdog = Timer.periodic(
            const Duration(milliseconds: 1500),
            (_) {
              // Use `mounted` (Flutter-disposal check) rather than just
              // `_disposed`: a periodic Timer tick can race the disposal
              // pipeline, and `ref` access after dispose throws.
              if (!mounted || _disposed) {
                _playWatchdog?.cancel();
                return;
              }
              if (!ref.read(playerControllerProvider).isPlaying) {
                _playWatchdog?.cancel();
                return;
              }
              // If iframe got stuck again (silent pause), reload to the
              // current audio time. The watchdog cost is one postMessage
              // per second which YT happily ignores when already playing.
              final secs = ref
                      .read(audioPlayerProvider)
                      .position
                      .inMilliseconds /
                  1000.0;
              final expected = _expectedVideoSecs();
              if ((secs - expected).abs() > 2.0) {
                final track = ref.read(playerControllerProvider).track;
                if (track != null) {
                  _postCommand('mute');
                  _postCommand('loadVideoById', [
                    track.id,
                    secs,
                    'default',
                  ]);
                  _suppressDriftUntil = DateTime.now().add(_loadGrace);
                  _anchorSecs = secs;
                  _anchorWall = DateTime.now();
                  _postCommand('playVideo');
                }
              }
            },
          );
        } else {
          _postCommand('pauseVideo');
          _setPlaying(false);
          _playWatchdog?.cancel();
          _playWatchdog = null;
        }
      }
    }, fireImmediately: true);

    final audioPlayer = ref.read(audioPlayerProvider);
    _positionSub = audioPlayer.positionStream.listen(_onAudioPosition);

    // Seed the iframe src up front so the DOM element always has a YT URL
    // from the very first frame. Without this the iframe's src stays empty
    // (since _loadVideo runs from the listener but doesn't rewrite src,
    // and the build-time src write is suppressed once _currentVideoId is
    // set) and YT never loads — leaving the iframe blank/white.
    // Use autoplay=audioPlaying so the URL matches the play state we'll
    // subsequently issue commands for.
    if (widget.videoId.isNotEmpty) {
      final audioPlaying = ref.read(playerControllerProvider).isPlaying;
      final desired = _embedUrl(widget.videoId, autoplay: audioPlaying);
      if (_iframe.src != desired) _iframe.src = desired;
    }
  }

  void _onAudioPosition(Duration pos) {
    final secs = pos.inMilliseconds / 1000.0;
    // Skip drift correction during the post-seek / post-load quiet window so
    // the audio player doesn't make us re-seek with stale transient values.
    if (DateTime.now().isBefore(_suppressDriftUntil)) return;
    final expected = _expectedVideoSecs();
    if ((secs - expected).abs() > _driftThreshold) {
      _postSeek(secs);
    }
  }

  @override
  void didUpdateWidget(YouTubeEmbed old) {
    super.didUpdateWidget(old);
    if (old.videoId != widget.videoId) {
      // Same gating as the listener: load with the right autoplay state.
      final isPlaying = ref.read(playerControllerProvider).isPlaying;
      _loadVideo(widget.videoId, autoplay: isPlaying);
      _iframe.src = _embedUrl(widget.videoId, autoplay: isPlaying);
    }
  }

  @override
  void dispose() {
    // Flip first so any synchronous listener fires between here and
    // super.dispose() are dropped by _postCommand.
    _disposed = true;
    _hideTimer?.cancel();
    _playWatchdog?.cancel();
    _positionSub?.cancel();
    _stateSub?.close();
    super.dispose();
  }

  // Swap the iframe to a new videoId. The URL embeds autoplay=1 when audio
  // is already playing so the iframe boots in sync; autoplay=0 otherwise so
  // it doesn't race ahead while audio is still loading.
  void _loadVideo(String videoId, {required bool autoplay}) {
    _currentVideoId = videoId;
    _iframe.dataset['mountEpoch'] = _mountEpoch.toString();
    // Same videoId → reload cleanly. A mode toggle (fullscreen / theater /
    // cover) rebuilds the widget tree; relying on stale JS state on the
    // shared iframe across mounts leaves it stuck on the thumbnail or in a
    // blank-buffering state. A loadVideoById with the current play time as
    // the start second guarantees YT is in the right state from the
    // iframe's point of view.
    if (_iframe.src.contains('/embed/$videoId?')) {
      final pos = ref.read(audioPlayerProvider).position.inMilliseconds /
          1000.0;
      final startAt = pos > 0 ? pos : 0.0;
      _postCommand('mute');
      _postCommand('loadVideoById', [videoId, startAt, 'default']);
      _suppressDriftUntil = DateTime.now().add(_loadGrace);
      _anchorSecs = startAt;
      _anchorWall = DateTime.now();
      _setPlaying(autoplay);
      if (autoplay) _postCommand('playVideo');
      return;
    }

    // Different video, or first ever load: full sequence.
    _postCommand('mute');
    _postCommand('loadVideoById', [videoId, 0, 'default']);
    _suppressDriftUntil = DateTime.now().add(_loadGrace);
    _anchorSecs = 0;
    _anchorWall = DateTime.now();
    _setPlaying(autoplay);
    if (autoplay) {
      _postCommand('playVideo');
      // Defensive re-issue after YT finishes loading. Drop the postMessage
      // earlier than YT processes it and the playVideo silently fails, the
      // iframe sits at the thumbnail with audio already playing. A delayed
      // follow-up gives YT's API time to attach.
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (_disposed) return;
        if (ref.read(playerControllerProvider).isPlaying) {
          _postCommand('playVideo');
        }
      });
    }
  }

  // Estimated position of the video right now. While playing it advances with
  // wall-clock time from the last anchor; while paused it stays put.
  double _expectedVideoSecs() {
    if (!_videoPlaying) return _anchorSecs;
    return _anchorSecs +
        DateTime.now().difference(_anchorWall).inMilliseconds / 1000.0;
  }

  void _setPlaying(bool playing) {
    // Re-anchor on any play/pause transition so the estimate stays accurate.
    _anchorSecs = _expectedVideoSecs();
    _anchorWall = DateTime.now();
    _videoPlaying = playing;
  }

  void _postSeek(double seconds) {
    _anchorSecs = seconds;
    _anchorWall = DateTime.now();
    _suppressDriftUntil = DateTime.now().add(_seekQuietZone);
    _postCommand('seekTo', [seconds, true]);
  }

  void _postCommand(String func, [List<Object>? args]) {
    if (_disposed) return;
    // Drop stale commands from a previous mount. When theater ↔ fullscreen
    // swaps create a new YouTubeEmbed, this State is being replaced; a
    // still-queued pauseVideo from the old listener must not land after
    // the new mount's playVideo.
    final stored = _iframe.dataset['mountEpoch'];
    if (stored != _mountEpoch.toString()) return;
    final win = _iframe.contentWindow;
    if (win == null) return;
    final message = args == null
        ? '{"event":"command","func":"$func"}'
        : '{"event":"command","func":"$func","args":${jsonEncode(args)}}';
    win.postMessage(message.toJS, '*'.toJS);
  }

  String _embedUrl(String id, {required bool autoplay}) {
    // Standard youtube.com embed (not youtube-nocookie) so enablejsapi works.
    // Mute=1 always; autoplay tracks the audio state so the iframe never
    // races ahead of a still-loading audio source.
    final params = <String, String>{
      'enablejsapi': '1',
      'mute': '1',
      'controls': '0',
      'modestbranding': '1',
      'rel': '0',
      'playsinline': '1',
      'disablekb': '1',
      'autoplay': autoplay ? '1' : '0',
    };
    final qs = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    return 'https://www.youtube.com/embed/$id?$qs';
  }

  @override
  Widget build(BuildContext context) {
    // First-mount or track-id change: seed the iframe with the right autoplay
    // state to match audio. _iframe.src is shared across instances — guard
    // against re-writing it (which would reload the iframe and discard any
    // in-flight JS state from the previous mount).
    final audioPlaying = ref.read(playerControllerProvider).isPlaying;
    final desiredSrc = _embedUrl(widget.videoId, autoplay: audioPlaying);
    if (_currentVideoId == null) {
      _loadVideo(widget.videoId, autoplay: audioPlaying);
      if (_iframe.src != desiredSrc) _iframe.src = desiredSrc;
    } else if (_currentVideoId != widget.videoId) {
      _loadVideo(widget.videoId, autoplay: audioPlaying);
      if (_iframe.src != desiredSrc) _iframe.src = desiredSrc;
    }
    final isFs = widget.fullscreen;

    final body = _EmbedBody(
      onBumpControls: _bumpControls,
      onScrubInteraction: _onScrubInteraction,
      isFullscreen: isFs,
      showTheater: widget.showTheater,
      controlsVisible: _controlsVisible,
    );

    if (isFs) {
      // SizedBox.expand gives the Stack bounded constraints so StackFit.expand
      // can fill the screen — SafeArea alone passes unbounded height down,
      // which makes a Stack that uses StackFit.expand assert.
      return SizedBox.expand(
        child: _EscListener(
          onEscape: () => ref.read(fullscreenVideoProvider.notifier).set(false),
          child: MouseRegion(onHover: (_) => _bumpControls(), child: body),
        ),
      );
    }
    // Inline path: SizedBox.expand (a SizedBox with finite width & height
    // matching its parent) gives the Stack bounded constraints regardless
    // of the surrounding layout (e.g. a Column would otherwise hand down
    // unbounded height). SizedBox.expand fills the parent width but uses
    // a child-sized height — we then wrap in AspectRatio to give it a
    // definite box too. ClipRRect rounds the corners to match the panel
    // style so the video reads as a card, not a hard rectangle.
    return MouseRegion(
      onHover: (_) => _bumpControls(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_embedRadius),
        child: SizedBox(
          width: double.infinity,
          child: AspectRatio(aspectRatio: widget.aspectRatio, child: body),
        ),
      ),
    );
  }

  // Show the overlay; restart the auto-hide timer. Called from any pointer
  // activity over the video region.
  void _bumpControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideControlsAfter, () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
    });
  }

  // Scrubber tells us when the user is holding the thumb — keep the overlay
  // up the whole time so the drag stays visible.
  void _onScrubInteraction(bool active) {
    if (active) {
      _hideTimer?.cancel();
      if (!_controlsVisible) setState(() => _controlsVisible = true);
    } else {
      _bumpControls();
    }
  }
}

/// Gradient scrim behind the overlay row. Lifted out so the fullscreen variant
/// can render it without rebuilding the Row layout.
class _OverlayScrim extends StatelessWidget {
  const _OverlayScrim({required this.child, this.fullscreen = false});

  final Widget child;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: fullscreen
          ? const EdgeInsets.fromLTRB(16, 32, 16, 12)
          : const EdgeInsets.fromLTRB(8, 28, 8, 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.65),
            Colors.transparent,
          ],
        ),
      ),
      child: child,
    );
  }
}

/// Custom control drawn over the (pointer-inert) iframe. The iframe swallows
/// input, so these are the only clickable controls on the video.
class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}

/// Stack of iframe + tap-to-seek detector + scrim controls. Extracted from
/// `_YouTubeEmbedState.build` so the fullscreen Esc listener can wrap it
/// without distracting from the rest of the build.
class _EmbedBody extends ConsumerWidget {
  const _EmbedBody({
    required this.onBumpControls,
    required this.onScrubInteraction,
    required this.isFullscreen,
    required this.showTheater,
    required this.controlsVisible,
  });

  final VoidCallback onBumpControls;
  final ValueChanged<bool> onScrubInteraction;
  final bool isFullscreen;
  final bool showTheater;
  // While in fullscreen the overlay stays pinned; in inline mode it fades.
  final bool controlsVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theaterOn = ref.watch(theaterModeProvider);
    final isPlaying = ref.watch(
      playerControllerProvider.select((s) => s.isPlaying),
    );
    final thumbnailUrl = ref.watch(
      playerControllerProvider.select((s) => s.track?.thumbnail ?? ''),
    );
    // Inline mode auto-hides; fullscreen mode keeps controls visible (user
    // already owns the viewport, fading them out feels punishing).
    final showOverlay = isFullscreen || controlsVisible;
    return Stack(
      fit: isFullscreen ? StackFit.expand : StackFit.loose,
      children: [
        // YouTube-style ambient lighting: blurred thumbnail behind the
        // iframe. Self-guards on provider state + thumbnail availability.
        _AmbientBackdrop(thumbnailUrl: thumbnailUrl),
        Positioned.fill(child: HtmlElementView(viewType: _viewType)),
        // Slight darken on pause so the iframe reads as "stopped" without
        // the controls having to be open. AnimatedOpacity for a soft
        // transition; the controls scrim still draws on top so its bottom
        // gradient is unaffected.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: isPlaying ? 0.0 : 0.5,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
        // Tap-to-seek only on inline surfaces — in fullscreen the user
        // already owns the viewport and the scrubber is the primary control.
        if (!isFullscreen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTapDown: (d) {
                final w =
                    (context.findRenderObject() as RenderBox?)?.size.width ?? 1;
                final going =
                    d.localPosition.dx < w / 2 ? -_seekStepSec : _seekStepSec;
                final dur = ref
                    .read(audioPlayerProvider)
                    .duration
                    ?.inMilliseconds;
                final pos =
                    ref.read(audioPlayerProvider).position.inMilliseconds;
                if (dur == null || dur <= 0) return;
                final target = (pos + (going * 1000).round()).clamp(0, dur);
                ref.read(audioPlayerProvider).seek(
                  Duration(milliseconds: target),
                );
                onBumpControls();
              },
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            // Suppress hit-testing only when fully hidden (inline mode).
            ignoring: !showOverlay,
            child: AnimatedOpacity(
              opacity: showOverlay ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: _OverlayScrim(
                fullscreen: isFullscreen,
                child: Row(
                  children: [
                    Expanded(
                      child: HorizontalScrubber(
                        onVideo: true,
                        onInteractionChange: onScrubInteraction,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (showTheater && !isFullscreen) ...[
                      _OverlayButton(
                        icon: theaterOn
                            ? Icons.chevron_right
                            : Icons.width_wide_outlined,
                        tooltip: theaterOn
                            ? 'Exit theater mode'
                            : 'Theater mode',
                        onTap: () => ref
                            .read(theaterModeProvider.notifier)
                            .toggle(),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _OverlayButton(
                      icon: isFullscreen ? Icons.close : Icons.fullscreen,
                      tooltip:
                          isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
                      onTap: () {
                        if (isFullscreen) {
                          ref
                              .read(fullscreenVideoProvider.notifier)
                              .set(false);
                        } else {
                          ref
                              .read(fullscreenVideoProvider.notifier)
                              .toggle();
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    const _VideoSettingsButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// KeyboardListener wrapper that requests focus so Escape can exit fullscreen.
/// Only mounted in fullscreen mode.
class _EscListener extends StatefulWidget {
  const _EscListener({required this.child, required this.onEscape});
  final Widget child;
  final VoidCallback onEscape;

  @override
  State<_EscListener> createState() => _EscListenerState();
}

class _EscListenerState extends State<_EscListener> {
  final _focus = FocusNode(debugLabel: 'youtube-fullscreen-esc');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (e) {
        if (e is! KeyDownEvent) return;
        if (e.logicalKey != LogicalKeyboardKey.escape) return;
        widget.onEscape();
      },
      child: widget.child,
    );
  }
}

/// YouTube-style ambient lighting. Renders a heavily-blurred, scaled-up
/// version of the current track's thumbnail behind the iframe so the video
/// appears to bleed color into the surrounding panel. Skips rendering when
/// [ambientLightingProvider] is off or no thumbnail URL is available —
/// callers don't need to guard.
class _AmbientBackdrop extends ConsumerWidget {
  const _AmbientBackdrop({required this.thumbnailUrl});

  final String thumbnailUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (thumbnailUrl.isEmpty) return const SizedBox.shrink();
    final enabled = ref.watch(ambientLightingProvider);
    if (!enabled) return const SizedBox.shrink();
    // Positioned.fill needs a Stack with bounded constraints — _EmbedBody
    // wraps us in either AspectRatio (inline) or SizedBox.expand (fs).
    return Positioned.fill(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
        child: Transform.scale(
          // Scale up so the blur sigma doesn't reveal an edge — by 1.6x the
          // blurred edges land well outside the visible frame for our
          // typical embed sizes.
          scale: 1.6,
          child: Image.network(
            thumbnailUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// Settings button + popup menu. Currently exposes the ambient lighting
/// toggle; future player-level settings land here.
class _VideoSettingsButton extends ConsumerWidget {
  const _VideoSettingsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _OverlayButton(
      icon: Icons.tune,
      tooltip: 'Settings',
      onTap: () => _showAmbientMenu(context, ref),
    );
  }
}

void _showAmbientMenu(BuildContext context, WidgetRef ref) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null) return;
  final overlayBox =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlayBox == null) return;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  showMenu<void>(
    context: context,
    position: RelativeRect.fromRect(rect, Offset.zero & overlayBox.size),
    items: [
      CheckedPopupMenuItem(
        checked: ref.read(ambientLightingProvider),
        child: const Text('Ambient lighting'),
        onTap: () =>
            ref.read(ambientLightingProvider.notifier).toggle(),
      ),
    ],
  );
}
