import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'big_player.dart';
import 'player_controller.dart';
import 'queue_provider.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key, this.floating = false});

  /// When true the widget renders as a rounded floating card (used on wide
  /// layouts docked to a corner). When false it renders edge-to-edge as a
  /// bottom bar (used on narrow layouts).
  final bool floating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final track = state.track;
    if (track == null) return const SizedBox.shrink();
    final hasNext = ref.watch(playbackQueueProvider.select((q) => q.hasNext));
    final hasPrevious = ref.watch(
      playbackQueueProvider.select((q) => q.hasPrevious),
    );

    final theme = Theme.of(context);
    final content = InkWell(
      onTap: () => showPlayerSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Hero(
              tag: playerCoverHeroTag(track.id),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 48,
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Image.network(
                      track.thumbnail,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.music_note, size: 20),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    track.uploader,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (state.isLoading)
              const SizedBox(
                width: 32,
                height: 32,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              IconButton(
                tooltip: 'Previous',
                iconSize: 22,
                onPressed: hasPrevious
                    ? () => ref.read(playbackQueueProvider.notifier).previous()
                    : null,
                icon: const Icon(Icons.skip_previous),
              ),
              IconButton(
                onPressed: state.error != null
                    ? null
                    : () => ref
                          .read(playerControllerProvider.notifier)
                          .togglePlayPause(),
                icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              IconButton(
                tooltip: 'Next',
                iconSize: 22,
                onPressed: hasNext
                    ? () => ref.read(playbackQueueProvider.notifier).next()
                    : null,
                icon: const Icon(Icons.skip_next),
              ),
            ],
          ],
        ),
      ),
    );

    if (!floating) {
      return Material(
        color: theme.colorScheme.surfaceContainerHigh,
        child: content,
      );
    }

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}
