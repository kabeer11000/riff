import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/search_result.dart';
import 'now_playing_indicator.dart';
import 'queue_provider.dart';
import 'track_context_menu.dart';

/// Reorderable, removable view of the playback queue. Renders inside the
/// big player's `SingleChildScrollView`, so the list itself is non-scrolling
/// and lets the page handle overflow.
class QueuePanel extends ConsumerWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(playbackQueueProvider);
    final remaining =
        state.tracks.length - (state.index + 1).clamp(0, state.tracks.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.isEmpty ? 'Up next' : 'Up next · $remaining',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!state.isEmpty)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () =>
                        ref.read(playbackQueueProvider.notifier).clear(),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          if (state.tracks.isEmpty)
            _Empty(theme: theme)
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              padding: EdgeInsets.zero,
              // ReorderableListView.onReorder passes newIndex before the
              // old row is removed (the pre-v3.41 contract). Queue.reorder
              // compensates for that shift; switching to onReorderItem
              // would double-shift.
              // ignore: deprecated_member_use
              onReorder: (oldIndex, newIndex) => ref
                  .read(playbackQueueProvider.notifier)
                  .reorder(oldIndex, newIndex),
              itemCount: state.tracks.length,
              itemBuilder: (context, i) {
                final track = state.tracks[i];
                final isCurrent = i == state.index;
                return _QueueRow(
                  key: ValueKey(track.id),
                  track: track,
                  index: i,
                  isCurrent: isCurrent,
                  onTap: () =>
                      ref.read(playbackQueueProvider.notifier).jumpTo(i),
                  onRemove: () =>
                      ref.read(playbackQueueProvider.notifier).removeAt(i),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _QueueRow extends ConsumerWidget {
  const _QueueRow({
    super.key,
    required this.track,
    required this.index,
    required this.isCurrent,
    required this.onTap,
    required this.onRemove,
  });

  final SearchResult track;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return TrackContextMenu(
      track: track,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isCurrent
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Icon(
                  Icons.drag_handle,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 2,
                  ),
                  child: Row(
                    children: [
                      _Thumb(url: track.thumbnail),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track.title.isEmpty ? 'Untitled' : track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: isCurrent
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            Text(
                              track.uploader.isEmpty
                                  ? 'Unknown'
                                  : track.uploader,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (isCurrent)
                        NowPlayingIndicator(trackId: track.id, size: 14)
                      else
                        Text(
                          '${index + 1}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Remove from queue',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              onPressed: onRemove,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        width: 40,
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.music_note, size: 16),
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          'Queue is empty — long-press a track to add it',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
