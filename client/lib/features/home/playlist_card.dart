import 'package:flutter/material.dart';

import '../../api/models/playlist.dart';

/// Square cover + name tile for the horizontal "Your playlists" scroll on the
/// home screen. Tapping is a stub until the playlist screen lands; we surface
/// a SnackBar so the UI feels real.
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({super.key, required this.playlist, this.onTap});
  final Playlist playlist;
  final VoidCallback? onTap;

  static const coverSize = 160.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: coverSize,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 1,
                child: playlist.coverUrl.isEmpty
                    ? Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.queue_music,
                          size: 36,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Image.network(
                        playlist.coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.queue_music,
                            size: 36,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              playlist.name.isEmpty ? 'Untitled' : playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}
