import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/endpoints/history.dart';
import '../../api/models/continue_card.dart';
import '../../api/models/history_entry.dart';

class HomeData {
  const HomeData({required this.entries, required this.continueCard});
  final List<HistoryEntry> entries;
  final ContinueCard? continueCard;
}

final homeDataProvider = FutureProvider.autoDispose<HomeData>((ref) async {
  final api = ref.watch(historyApiProvider);
  final r = await api.list(limit: 20);
  return HomeData(entries: r.entries, continueCard: r.continueCard);
});

// Shared subtitle for both the list tile and the grid card. We intentionally
// don't surface playCount here — the user shouldn't see how many times they've
// rewatched something.
String historySubtitle(HistoryEntry e) {
  final who = e.uploader.isEmpty ? 'Unknown' : e.uploader;
  if (e.isLongForm) {
    return _humanPosition(e.lastPosition);
  }
  if (e.contextTitle.isNotEmpty) {
    return 'From ${e.contextTitle}';
  }
  return who;
}

String _humanPosition(double secs) {
  final s = secs.round();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  if (h > 0) return '$h h ${m}m left';
  return '${m}m left';
}

/// Picks the uploader the user listens to most and returns their most-played
/// tracks. Returns null when there's no clear signal — sparse history or a
/// flat distribution across uploaders. Pure function over [entries]; lives in
/// the controller file so any future home surface can reuse it.
({String uploader, List<HistoryEntry> tracks})? topChannel(
    List<HistoryEntry> entries) {
  if (entries.length < 2) return null;
  final byUploader = <String, List<HistoryEntry>>{};
  for (final e in entries) {
    if (e.uploader.isEmpty) continue;
    (byUploader[e.uploader] ??= []).add(e);
  }
  if (byUploader.isEmpty) return null;
  String best = '';
  int bestPlays = -1;
  var bestRecent = DateTime.fromMillisecondsSinceEpoch(0);
  byUploader.forEach((u, list) {
    final plays = list.fold<int>(0, (a, e) => a + e.playCount);
    final recent = list
        .map((e) => e.lastPlayedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    if (plays > bestPlays ||
        (plays == bestPlays && recent.isAfter(bestRecent))) {
      best = u;
      bestPlays = plays;
      bestRecent = recent;
    }
  });
  if (best.isEmpty || bestPlays <= 1) return null;
  final tracks = (byUploader[best]!
        ..sort((a, b) => b.playCount.compareTo(a.playCount)))
      .take(6)
      .toList();
  return (uploader: best, tracks: tracks);
}

class HistoryTile extends ConsumerWidget {
  const HistoryTile({super.key, required this.entry, this.onTap});
  final HistoryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Thumb(entry: entry),
            const SizedBox(width: 16),
            Expanded(child: _Text(entry: entry, style: _TextStyle.row)),
          ],
        ),
      ),
    );
  }
}

/// Vertical cover-on-top card for the wide-screen grid. Reuses [historySubtitle]
/// and the long-form progress bar from [HistoryTile].
class HistoryGridCard extends StatelessWidget {
  const HistoryGridCard({super.key, required this.entry, this.onTap});
  final HistoryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: _ThumbArt(
                  url: entry.thumbnail,
                  videoId: entry.videoId,
                  radius: 10,
                  progress: entry.isLongForm && entry.duration > 0
                      ? entry.lastPosition / entry.duration
                      : null,
                  minutesLeft: entry.isLongForm ? _humanPosition(entry.lastPosition) : null,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _Text(entry: entry, style: _TextStyle.card),
          ],
        ),
      ),
    );
  }
}

enum _TextStyle { row, card }

class _Text extends StatelessWidget {
  const _Text({required this.entry, required this.style});
  final HistoryEntry entry;
  final _TextStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = style == _TextStyle.card
        ? theme.textTheme.titleSmall
        : theme.textTheme.titleMedium;
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          entry.title.isEmpty ? 'Untitled' : entry.title,
          maxLines: style == _TextStyle.card ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        const SizedBox(height: 2),
        Text(
          historySubtitle(entry),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: subtitleStyle,
        ),
      ],
    );
  }
}

/// "Continue `playlist/channel`" card. Tapping is a no-op stub until the
/// playlist/channel screens land; we surface a SnackBar so the UI feels real.
class ContinueCardTile extends StatelessWidget {
  const ContinueCardTile({super.key, required this.card});
  final ContinueCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Semantics(
        button: true,
        label: 'Continue ${card.title}',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${card.kind[0].toUpperCase()}${card.kind.substring(1)} view coming soon'),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    card.kind == 'channel' ? Icons.person_outline : Icons.queue_music,
                    size: 28,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Continue',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        card.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.play_arrow,
                  color: theme.colorScheme.primary,
                  size: 32,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.entry});
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final progress = entry.isLongForm && entry.duration > 0
        ? entry.lastPosition / entry.duration
        : null;
    return SizedBox(
      width: 56,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: _ThumbArt(
          url: entry.thumbnail,
          videoId: entry.videoId,
          radius: 6,
          progress: progress,
        ),
      ),
    );
  }
}

class _ThumbArt extends StatelessWidget {
  const _ThumbArt({
    required this.url,
    required this.videoId,
    required this.radius,
    this.progress,
    this.minutesLeft,
  });
  final String url;
  final String videoId;
  final double radius;
  final double? progress;
  final String? minutesLeft;

  @override
  Widget build(BuildContext context) {
    final src = url.isEmpty ? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg' : url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            src,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(
                child: Icon(Icons.music_note, size: 28),
              ),
            ),
          ),
          if (progress != null || minutesLeft != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _Overlay(progress: progress, minutesLeft: minutesLeft),
            ),
        ],
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({this.progress, this.minutesLeft});
  final double? progress;
  final String? minutesLeft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (minutesLeft != null)
              Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  margin: const EdgeInsets.all(4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.5),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    minutesLeft!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            if (progress != null)
              SizedBox(
                width: constraints.maxWidth,
                height: 3,
                child: LinearProgressIndicator(
                  value: progress!.clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
                ),
              ),
          ],
        );
      },
    );
  }
}
