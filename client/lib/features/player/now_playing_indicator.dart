import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'player_controller.dart';

/// Spotify-style equalizer indicator. Animates three vertical bars when the
/// given [trackId] is the currently-playing track, shows a static mini-bars
/// glyph when the track is loaded but paused, and renders nothing when it's
/// neither the current track nor paused on it.
class NowPlayingIndicator extends ConsumerStatefulWidget {
  const NowPlayingIndicator({
    super.key,
    required this.trackId,
    this.size = 14,
    this.color,
  });

  final String trackId;
  final double size;
  final Color? color;

  @override
  ConsumerState<NowPlayingIndicator> createState() =>
      _NowPlayingIndicatorState();
}

class _NowPlayingIndicatorState extends ConsumerState<NowPlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerControllerProvider);
    final isCurrent = state.track?.id == widget.trackId;
    final isPlaying = isCurrent && state.isPlaying;

    if (isPlaying && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!isPlaying && _ctrl.isAnimating) {
      _ctrl.stop();
    }

    if (!isCurrent) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final color = widget.color ?? theme.colorScheme.primary;
    // Slightly dimmer when paused so it reads as "loaded but not playing".
    final effective = isPlaying ? color : color.withValues(alpha: 0.55);
    final w = widget.size / 5;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _Bar(
            controller: _ctrl,
            phase: 0.0,
            color: effective,
            width: w,
            isPlaying: isPlaying,
          ),
          _Bar(
            controller: _ctrl,
            phase: 0.33,
            color: effective,
            width: w,
            isPlaying: isPlaying,
          ),
          _Bar(
            controller: _ctrl,
            phase: 0.66,
            color: effective,
            width: w,
            isPlaying: isPlaying,
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.controller,
    required this.phase,
    required this.color,
    required this.width,
    required this.isPlaying,
  });

  final AnimationController controller;
  final double phase;
  final Color color;
  final double width;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        // Cosine-driven height: smooth oscillation between 30% and 100%.
        // When paused, snap to a static low/medium/high glyph.
        final t = isPlaying ? (controller.value + phase) % 1.0 : phase;
        final normalized = 0.5 - 0.5 * math.cos(t * 2 * math.pi);
        final h = (0.3 + 0.7 * normalized);
        return Container(
          width: width,
          height:
              h * 18, // bar pixel height; the parent SizedBox bounds the row
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(width / 2),
          ),
        );
      },
    );
  }
}
