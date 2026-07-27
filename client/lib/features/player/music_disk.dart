import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'big_player.dart';
import 'player_controller.dart';
import 'queue_provider.dart';

const _coverRadius = 12.0;

const _diskSize = 220.0;
const _diskBody = 210.0;
const _ringStroke = 6.0;
const _center = Offset(_diskSize / 2, _diskSize / 2);

/// Square cover art for the big player. The Hero destination (matches the
/// miniplayer tag) so tapping the miniplayer cover morphs into this image.
/// A small play/pause button sits at the bottom-right of the cover.
class CoverArt extends ConsumerWidget {
  const CoverArt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final track = state.track;
    if (track == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final player = ref.read(audioPlayerProvider);
    return Hero(
      tag: playerCoverHeroTag(track.id),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, posSnap) {
            return StreamBuilder<Duration?>(
              stream: player.durationStream,
              builder: (context, durSnap) {
                final pos = posSnap.data ?? Duration.zero;
                final dur = durSnap.data ?? Duration.zero;
                final fraction = dur.inMilliseconds > 0
                    ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                    : 0.0;
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(_coverRadius),
                      child: SizedBox.expand(
                        child: Image.network(
                          track.thumbnail.isEmpty
                              ? 'https://i.ytimg.com/vi/${track.id}/hqdefault.jpg'
                              : track.thumbnail,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Center(
                              child: Icon(Icons.music_note, size: 48),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: GestureDetector(
                        onTap: state.isLoading
                            ? null
                            : () => ref
                                  .read(playerControllerProvider.notifier)
                                  .togglePlayPause(),
                        child: state.isLoading
                            ? const SizedBox(
                                width: 44,
                                height: 44,
                                child: Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              )
                            : Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  state.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 28,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              ),
                      ),
                    ),
                    // YouTube-style thin progress bar across the very bottom of
                    // the cover. The track sits above the play button's bottom
                    // margin so they don't overlap visually.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _CoverProgressBar(fraction: fraction),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Thin progress bar pinned to the bottom of the cover image. Matches the
/// radius of the cover so the filled portion tucks under the rounded corner.
class _CoverProgressBar extends StatelessWidget {
  const _CoverProgressBar({required this.fraction});
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: LayoutBuilder(
        builder: (context, c) {
          return Stack(
            children: [
              Container(color: Colors.white.withValues(alpha: 0.18)),
              FractionallySizedBox(
                widthFactor: fraction,
                child: Container(color: Colors.white),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Circular scrubber disk. The disk body spins while playing; tap anywhere
/// to toggle play/pause; drag to scrub via the disk's angle. The progress
/// ring around the edge shows fractional playback.
class MusicDisk extends ConsumerStatefulWidget {
  const MusicDisk({super.key});

  @override
  ConsumerState<MusicDisk> createState() => _MusicDiskState();
}

class _MusicDiskState extends ConsumerState<MusicDisk>
    with SingleTickerProviderStateMixin {
  // Scrub gesture state. Captured at pan-start so wraparound across 12 o'clock
  // doesn't teleport (we clamp delta to [-π, π]).
  double? _startAngle;
  double? _startFraction;
  double? _scrubFraction;
  // Rotation (radians) at the moment the scrub started. The disc continues
  // from here as the user drags, so the gesture feels continuous with the
  // auto-spin that was running a moment ago.
  double _scrubStartRotation = 0;
  // Accumulated angular delta (radians) of the current scrub gesture.
  double _scrubDelta = 0;
  // Tap-down scale for the springy press feedback. Snaps to 0.92 on tap, then
  // AnimatedScale springs back to 1.0.
  double _pressScale = 1.0;

  // One full rotation every 12s while playing.
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerControllerProvider);
    final theme = Theme.of(context);
    final player = ref.read(audioPlayerProvider);

    if (state.isPlaying) {
      if (!_spinController.isAnimating) _spinController.repeat();
    } else if (_spinController.isAnimating) {
      _spinController.stop();
    }

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, posSnap) {
        return StreamBuilder<Duration?>(
          stream: player.durationStream,
          builder: (context, durSnap) {
            final pos = posSnap.data ?? Duration.zero;
            final dur = durSnap.data ?? Duration.zero;
            final fraction =
                _scrubFraction ??
                (dur.inMilliseconds > 0
                    ? pos.inMilliseconds / dur.inMilliseconds
                    : 0.0);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: state.isLoading
                  ? null
                  : () {
                      _triggerPress();
                      ref
                          .read(playerControllerProvider.notifier)
                          .togglePlayPause();
                    },
              onPanStart: (d) {
                if (dur.inMilliseconds <= 0) return;
                _startAngle = _angleFromCenter(d.localPosition);
                _startFraction = fraction;
                _scrubStartRotation = _spinController.value * 2 * math.pi;
                _scrubDelta = 0;
                // Hand control of the rotation to the drag until the user
                // releases; the auto-spin resumes from the current angle.
                _spinController.stop();
              },
              onPanUpdate: (d) {
                if (_startAngle == null) return;
                final newAngle = _angleFromCenter(d.localPosition);
                var delta = newAngle - _startAngle!;
                if (delta > math.pi) delta -= 2 * math.pi;
                if (delta < -math.pi) delta += 2 * math.pi;
                _scrubDelta = delta;
                final next = (_startFraction! + delta / (2 * math.pi)).clamp(
                  0.0,
                  1.0,
                );
                setState(() => _scrubFraction = next);
              },
              onPanEnd: (_) {
                if (_scrubFraction != null && dur.inMilliseconds > 0) {
                  final target = (_scrubFraction! * dur.inMilliseconds).round();
                  player.seek(Duration(milliseconds: target));
                }
                // Resume the spin from the angle the drag left the disc at
                // (mod 2π so the controller's 0–1 range stays in bounds).
                if (state.isPlaying) {
                  final resumed = _scrubStartRotation + _scrubDelta;
                  _spinController.value = (resumed / (2 * math.pi)) % 1.0;
                  _spinController.repeat();
                }
                setState(() {
                  _startAngle = null;
                  _startFraction = null;
                  _scrubFraction = null;
                });
              },
              child: SizedBox(
                width: _diskSize,
                height: _diskSize,
                child: AnimatedScale(
                  scale: _pressScale,
                  duration: const Duration(milliseconds: 200),
                  curve: const Cubic(0.25, 1.1, 0.5, 1.0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Progress ring (does not rotate; it shows fractional progress)
                      SizedBox(
                        width: _diskSize,
                        height: _diskSize,
                        child: CustomPaint(
                          painter: _ProgressRingPainter(
                            fraction: fraction,
                            color: theme.colorScheme.primary,
                            backgroundColor: theme.colorScheme.onSurface
                                .withValues(alpha: 0.12),
                            strokeWidth: _ringStroke,
                          ),
                        ),
                      ),
                      // Spinning disk body — uses a textured metal image with
                      // a white background. We scale it up to fill the circle
                      // so the padding on the source PNG is cropped out.
                      AnimatedBuilder(
                        animation: _spinController,
                        builder: (_, child) {
                          final angle = _scrubFraction != null
                              ? _scrubStartRotation + _scrubDelta
                              : _spinController.value * 2 * math.pi;
                          return Transform.rotate(angle: angle, child: child);
                        },
                        child: Container(
                          width: _diskBody,
                          height: _diskBody,
                          clipBehavior: Clip.antiAlias,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x2E000000),
                                blurRadius: 18,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Transform.scale(
                            // Scale past 1.0 to push the source PNG's white
                            // padding outside the visible circle, then clip
                            // to the circle shape.
                            scale: 1.25,
                            child: Image.asset(
                              'assets/icons/disk/disk-texture-circle.png',
                              fit: BoxFit.cover,
                              width: _diskBody,
                              height: _diskBody,
                            ),
                          ),
                        ),
                      ),
                      if (state.isLoading)
                        const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Snap the disc down to 0.92 then let AnimatedScale spring it back to 1.0.
  // The 60ms hold mimics a physical button being pressed before it rebounds.
  void _triggerPress() {
    HapticFeedback.lightImpact();
    setState(() => _pressScale = 0.92);
    Future<void>.delayed(const Duration(milliseconds: 60), () {
      if (mounted) setState(() => _pressScale = 1.0);
    });
  }

  // Angle in radians from 12 o'clock clockwise, normalized to [0, 2π).
  static double _angleFromCenter(Offset local) {
    final dx = local.dx - _center.dx;
    final dy = local.dy - _center.dy;
    final a = math.atan2(dy, dx) + math.pi / 2;
    return (a + 2 * math.pi) % (2 * math.pi);
  }
}

/// YouTube-style horizontal seek bar shown in place of the disk when the
/// video tab is active. Reuses the same position/duration streams and seek.
class HorizontalScrubber extends ConsumerStatefulWidget {
  const HorizontalScrubber({
    super.key,
    this.onVideo = false,
    this.onInteractionChange,
  });

  // When true, styles for legibility over a video (white text/icons, tighter
  // padding) so it can be overlaid on the embed's scrim.
  final bool onVideo;

  // Optional notifier fired with true while the user is dragging the thumb
  // and false on release. Used by the YouTube embed to keep its overlay
  // visible during a scrub.
  final ValueChanged<bool>? onInteractionChange;

  @override
  ConsumerState<HorizontalScrubber> createState() => _HorizontalScrubberState();
}

class _HorizontalScrubberState extends ConsumerState<HorizontalScrubber> {
  // Non-null while dragging the thumb; suppresses the stream-driven position
  // so the thumb tracks the finger and only seeks on release.
  double? _scrubValue;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerControllerProvider);
    final theme = Theme.of(context);
    final player = ref.read(audioPlayerProvider);
    final fg = widget.onVideo ? Colors.white : null;
    final timeStyle = theme.textTheme.labelMedium?.copyWith(color: fg);

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, posSnap) {
        return StreamBuilder<Duration?>(
          stream: player.durationStream,
          builder: (context, durSnap) {
            final pos = posSnap.data ?? Duration.zero;
            final dur = durSnap.data ?? Duration.zero;
            final hasDur = dur.inMilliseconds > 0;
            final fraction =
                _scrubValue ??
                (hasDur
                    ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                    : 0.0);
            final elapsed = _scrubValue != null && hasDur
                ? Duration(
                    milliseconds: (_scrubValue! * dur.inMilliseconds).round(),
                  )
                : pos;
            final hasNext = ref.watch(
              playbackQueueProvider.select((q) => q.hasNext),
            );
            final hasPrevious = ref.watch(
              playbackQueueProvider.select((q) => q.hasPrevious),
            );
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.onVideo ? 0 : 4),
              child: Row(
                children: [
                  IconButton(
                    iconSize: 28,
                    color: fg,
                    tooltip: 'Previous',
                    onPressed: state.isLoading || !hasPrevious
                        ? null
                        : () => ref
                            .read(playbackQueueProvider.notifier)
                            .previous(),
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  IconButton(
                    iconSize: 36,
                    color: fg,
                    onPressed: state.isLoading
                        ? null
                        : () => ref
                              .read(playerControllerProvider.notifier)
                              .togglePlayPause(),
                    icon: Icon(
                      state.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  IconButton(
                    iconSize: 28,
                    color: fg,
                    tooltip: 'Next',
                    onPressed: state.isLoading || !hasNext
                        ? null
                        : () => ref
                            .read(playbackQueueProvider.notifier)
                            .next(),
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                  Text(_fmtDuration(elapsed), style: timeStyle),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                        activeTrackColor: widget.onVideo
                            ? theme.colorScheme.primary
                            : null,
                        thumbColor: widget.onVideo ? Colors.white : null,
                        inactiveTrackColor: widget.onVideo
                            ? Colors.white.withValues(alpha: 0.3)
                            : null,
                      ),
                      child: Slider(
                        value: fraction,
                        onChangeStart: hasDur
                            ? (_) => widget.onInteractionChange?.call(true)
                            : null,
                        onChanged: hasDur
                            ? (v) => setState(() => _scrubValue = v)
                            : null,
                        onChangeEnd: hasDur
                            ? (v) {
                                player.seek(
                                  Duration(
                                    milliseconds: (v * dur.inMilliseconds)
                                        .round(),
                                  ),
                                );
                                setState(() => _scrubValue = null);
                                widget.onInteractionChange?.call(false);
                              }
                            : null,
                      ),
                    ),
                  ),
                  Text(
                    hasDur
                        ? _fmtRemaining(
                            Duration(
                              milliseconds:
                                  (dur.inMilliseconds - elapsed.inMilliseconds)
                                      .clamp(0, dur.inMilliseconds),
                            ),
                          )
                        : '--:--',
                    style: timeStyle,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

String _fmtDuration(Duration d) {
  final s = d.inSeconds;
  final m = s ~/ 60;
  final ss = (s % 60).toString().padLeft(2, '0');
  final h = m ~/ 60;
  if (h > 0) {
    final mm = (m % 60).toString().padLeft(2, '0');
    return '$h:$mm:$ss';
  }
  return '$m:$ss';
}

// YouTube-style "remaining" formatter. Clamps to 0 when the value goes
// negative (during a transient over-shoot, e.g. while scrubbing past the
// end) so the label never shows a misleading minus-one-second value.
String _fmtRemaining(Duration d) {
  final clamped = d.isNegative ? Duration.zero : d;
  return '-${_fmtDuration(clamped)}';
}

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({
    required this.fraction,
    required this.color,
    required this.backgroundColor,
    required this.strokeWidth,
  });

  final double fraction;
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth / 2;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    if (fraction > 0) {
      final fgPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      const startAngle = -math.pi / 2;
      final sweepAngle = 2 * math.pi * fraction;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        fgPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
