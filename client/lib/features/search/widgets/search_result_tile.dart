import 'package:flutter/material.dart';

import '../../../api/models/search_result.dart';
import '../../player/track_context_menu.dart';

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({super.key, required this.result, required this.onTap});
  final SearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TrackContextMenu(
      track: result,
      child: ListTile(
        onTap: onTap,
        leading: _Thumb(url: result.thumbnail, videoId: result.id),
        title: Text(result.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${result.uploader.isEmpty ? "Unknown" : result.uploader}'
          '${result.duration > 0 ? " • ${_fmt(result.duration)}" : ""}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }

  static String _fmt(double seconds) {
    final s = seconds.round();
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.videoId});
  final String url;
  final String videoId;

  @override
  Widget build(BuildContext context) {
    final fallback = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    final src = url.isEmpty ? fallback : url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 64,
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Image.network(
            src,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.music_note, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}