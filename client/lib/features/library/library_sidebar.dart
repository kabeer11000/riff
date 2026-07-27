import 'package:flutter/material.dart';

import '../../app/brand_logo.dart';
import '../../app/theme.dart';

/// Permanent left-side library panel for desktop layouts. Hosts the brand
/// wordmark at the top and the user's library (playlists, saved albums,
/// etc.) below. Collapses to an empty list once the user has nothing saved.
class LibrarySidebar extends StatelessWidget {
  const LibrarySidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? AppPalette.maroonDeep
            : theme.colorScheme.surfaceContainer,
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        right: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: BrandLogo(height: 28),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Library',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Create playlist',
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Create playlist coming soon'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.library_music_outlined,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No playlists yet',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
