import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ambient_lighting_provider.dart';
import 'player_controller.dart';

/// YouTube-style ambient lighting backdrop. A heavily-blurred version of the
/// current track's cover art, sized to extend beyond its caller (typically
/// a card-shaped cover/video) so the bleed is visible as a soft glow around
/// the card edges. Self-guards on the toggle and thumbnail availability so
/// callers can drop it into a Stack unconditionally.
class AmbientBackdrop extends ConsumerWidget {
  const AmbientBackdrop({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(ambientLightingProvider);
    if (!enabled) return const SizedBox.shrink();
    final thumb = ref.watch(
      playerControllerProvider.select((s) => s.track?.thumbnail ?? ''),
    );
    if (thumb.isEmpty) return const SizedBox.shrink();
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
      child: Image.network(
        thumb,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}
