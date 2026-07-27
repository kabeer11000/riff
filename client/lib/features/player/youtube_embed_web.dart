import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import 'music_disk.dart';
import 'player_controller.dart';
import 'video_fullscreen_provider.dart';
import 'video_tab_provider.dart';

const _seekStepSec = 10.0;
const _loadGrace = Duration(seconds: 2);
const _seekQuietZone = Duration(milliseconds: 600);
const _driftThreshold = 1.5;
const _viewType = 'riff-youtube-embed';

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

  // Auto-hide overlay controls (YouTube-style). True = visible. The overlay
  // also stays visible while the user is scrubbing or holding a button.
  bool _controlsVisible = true;
  Timer? _hideTimer;

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

    _stateSub = ref.listenManual<PlayerState>(playerControllerProvider, (
      prev,
      next,
    ) {
      // Track id change: swap the iframe's video.
      final prevId = prev?.track?.id;
      final nextId = next.track?.id;
      if (nextId != null && nextId != prevId) {
        _loadVideo(nextId);
        // Keep .src in sync with the postMessage-based loadVideoById — some
        // browsers / YT versions don't honor commands sent before the API is
        // ready, so a src assignment is the belt-and-braces fallback that
        // guarantees the iframe actually loads.
        _iframe.src = _embedUrl(nextId);
      }
      // Play/pause.
      final wasPlaying = prev?.isPlaying ?? false;
      final isPlaying = next.isPlaying;
      if (isPlaying != wasPlaying) {
        if (isPlaying) {
          _postCommand('playVideo');
          _setPlaying(true);
        } else {
          _postCommand('pauseVideo');
          _setPlaying(false);
        }
      }
    }, fireImmediately: true);

    final audioPlayer = ref.read(audioPlayerProvider);
    _positionSub = audioPlayer.positionStream.listen(_onAudioPosition);

    // Seed the iframe src up front, before any HtmlElementView is mounted.
    // Doing it here (instead of during build) guarantees the DOM sees a
    // populated src the moment the platform view is created.
    if (widget.videoId.isNotEmpty) {
      _iframe.src = _embedUrl(widget.videoId);
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
      _loadVideo(widget.videoId);
      _iframe.src = _embedUrl(widget.videoId);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _positionSub?.cancel();
    _stateSub?.close();
    super.dispose();
  }

  // Swap the iframe to a new videoId. loadVideoById(id, 0) seeks to 0 and
  // loads in one message, and YT buffers follow-up playVideo/pauseVideo
  // commands until the iframe API is ready.
  void _loadVideo(String videoId) {
    _currentVideoId = videoId;
    // Re-assert mute on every load in case it leaked through somehow.
    _postCommand('mute');
    _postCommand('loadVideoById', [videoId, 0, 'default']);
    _suppressDriftUntil = DateTime.now().add(_loadGrace);
    _anchorSecs = 0;
    _anchorWall = DateTime.now();
    final isPlaying = ref.read(playerControllerProvider).isPlaying;
    _setPlaying(isPlaying);
    if (isPlaying) {
      _postCommand('playVideo');
      // Defensive re-issue: the first playVideo postMessage can race ahead
      // of the iframe API initializing and be dropped. With autoplay=1 in
      // the URL the iframe still boots on its own, but if our state has
      // flipped to playing we also want our manual sync command to take
      // effect so pause-from-audio-player works immediately.
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
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
    final win = _iframe.contentWindow;
    if (win == null) return;
    final message = args == null
        ? '{"event":"command","func":"$func"}'
        : '{"event":"command","func":"$func","args":${jsonEncode(args)}}';
    win.postMessage(message.toJS, '*'.toJS);
  }

  String _embedUrl(String id) {
    // Standard youtube.com embed (not youtube-nocookie) so enablejsapi works.
    // autoplay=1 with mute=1 lets the iframe start on its own — if any of our
    // postMessages race ahead of the iframe API loading, the iframe still
    // begins playing instead of sitting on a black frame.
    const params = {
      'enablejsapi': '1',
      'mute': '1',
      'controls': '0',
      'modestbranding': '1',
      'rel': '0',
      'playsinline': '1',
      'disablekb': '1',
      'autoplay': '1',
    };
    final qs = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    return 'https://www.youtube.com/embed/$id?$qs';
  }

  @override
  Widget build(BuildContext context) {
    // First-mount initialization. _iframe.src is shared across all instances
    // so guard against reassigning the same URL — re-setting src on a
    // loaded iframe can trigger a needless reload.
    if (_currentVideoId == null) {
      _loadVideo(widget.videoId);
      _iframe.src = _embedUrl(widget.videoId);
    } else if (_currentVideoId != widget.videoId) {
      _loadVideo(widget.videoId);
      _iframe.src = _embedUrl(widget.videoId);
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
    // definite box too.
    return MouseRegion(
      onHover: (_) => _bumpControls(),
      child: SizedBox(
        width: double.infinity,
        child: AspectRatio(aspectRatio: widget.aspectRatio, child: body),
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
    // Inline mode auto-hides; fullscreen mode keeps controls visible (user
    // already owns the viewport, fading them out feels punishing).
    final showOverlay = isFullscreen || controlsVisible;
    return Stack(
      fit: isFullscreen ? StackFit.expand : StackFit.loose,
      children: [
        Positioned.fill(child: HtmlElementView(viewType: _viewType)),
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
