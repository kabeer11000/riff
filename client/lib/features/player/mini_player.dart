import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'big_player.dart';
import 'player_controller.dart';

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
                      track.thumbnail.isEmpty
                          ? 'https://i.ytimg.com/vi/${track.id}/hqdefault.jpg'
                          : track.thumbnail,
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
            else
              IconButton(
                onPressed: state.error != null
                    ? null
                    : () => ref
                          .read(playerControllerProvider.notifier)
                          .togglePlayPause(),
                icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
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
