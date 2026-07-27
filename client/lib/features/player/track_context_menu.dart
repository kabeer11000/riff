import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/endpoints/history.dart';
import '../../api/models/history_entry.dart';
import '../../api/models/search_result.dart';
import '../home/recent_list_controller.dart';
import 'queue_provider.dart';

/// Show a Material popup menu for a track at [tapPosition]. Pass
/// [isHistoryItem]=true to include the "Remove from history" action,
/// which only makes sense for HistoryTile (and triggers a home-data
/// refresh). Other actions work from any source (search, history, queue).
///
/// Trigger: wrap a track tile with a GestureDetector and call this from
/// [GestureDetector.onLongPressStart] using `details.globalPosition`.
Future<void> showTrackContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required SearchResult track,
  required Offset tapPosition,
  bool isHistoryItem = false,
}) async {
  final actions = <_MenuAction>[
    _MenuAction(
      icon: Icons.playlist_add,
      label: 'Add to queue',
      onSelected: () {
        ref.read(playbackQueueProvider.notifier).addToQueue(track);
        _snack(context, 'Added to queue');
      },
    ),
    _MenuAction(
      icon: Icons.playlist_play,
      label: 'Play next',
      onSelected: () {
        ref.read(playbackQueueProvider.notifier).playNext(track);
        _snack(context, 'Will play next');
      },
    ),
    _MenuAction(
      icon: Icons.person_outline,
      label: 'Go to artist',
      onSelected: () {
        // Artist screen isn't built yet. Show a teaser so the menu
        // item isn't a dead affordance.
        _snack(context, 'Artist page coming soon');
      },
    ),
    _MenuAction(
      icon: Icons.link,
      label: 'Copy link',
      onSelected: () async {
        await Clipboard.setData(ClipboardData(
          text: 'https://www.youtube.com/watch?v=${track.id}',
        ));
        if (!context.mounted) return;
        _snack(context, 'Link copied');
      },
    ),
  ];

  if (isHistoryItem) {
    actions.add(_MenuAction(
      icon: Icons.delete_outline,
      label: 'Remove from history',
      destructive: true,
      onSelected: () async {
        try {
          await ref.read(historyApiProvider).deleteTrack(track.id);
          // Refresh the home list so the entry disappears without a
          // pull-to-refresh.
          ref.invalidate(homeDataProvider);
          if (!context.mounted) return;
          _snack(context, 'Removed from history');
        } catch (_) {
          if (!context.mounted) return;
          _snack(context, 'Could not remove from history');
        }
      },
    ));
  }

  final overlayBox =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlayBox == null) return;
  // Anchor the menu at the tap point. showMenu uses the available
  // space — it flips to the other side if there's no room above/below.
  final position = RelativeRect.fromLTRB(
    tapPosition.dx,
    tapPosition.dy,
    overlayBox.size.width - tapPosition.dx,
    overlayBox.size.height - tapPosition.dy,
  );

  await showMenu<void>(
    context: context,
    position: position,
    items: [
      for (final a in actions)
        PopupMenuItem<void>(
          onTap: a.onSelected,
          child: Row(
            children: [
              Icon(a.icon,
                  size: 20,
                  color: a.destructive
                      ? Theme.of(context).colorScheme.error
                      : null),
              const SizedBox(width: 14),
              Text(a.label,
                  style: a.destructive
                      ? TextStyle(color: Theme.of(context).colorScheme.error)
                      : null),
            ],
          ),
        ),
    ],
  );
}

/// Wraps [child] so both touch long-press and desktop/web right-click open
/// the track context menu at the pointer. Tap is left to [child] (InkWell,
/// ListTile, ...) — these gestures don't conflict.
class TrackContextMenu extends ConsumerWidget {
  const TrackContextMenu({
    super.key,
    required this.track,
    required this.child,
    this.isHistoryItem = false,
  });
  final SearchResult track;
  final Widget child;
  final bool isHistoryItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void show(Offset at) => showTrackContextMenu(
          context: context,
          ref: ref,
          track: track,
          tapPosition: at,
          isHistoryItem: isHistoryItem,
        );
    return GestureDetector(
      onLongPressStart: (d) => show(d.globalPosition),
      onSecondaryTapDown: (d) => show(d.globalPosition),
      child: child,
    );
  }
}

/// Construct a SearchResult from a HistoryEntry so the context menu can
/// reuse the SearchResult API. SearchResult.type is approximate — the
/// backend doesn't tag history entries with type, so we infer long-form
/// vs short-form from the duration threshold used elsewhere (10 min).
SearchResult searchResultFromHistory(HistoryEntry e) => SearchResult(
      id: e.videoId,
      title: e.title,
      uploader: e.uploader,
      duration: e.duration,
      thumbnail: e.thumbnail,
      type: e.duration >= 600 ? 'video' : 'audio',
    );

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}

class _MenuAction {
  const _MenuAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onSelected;
  final bool destructive;
}
