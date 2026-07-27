import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/history_entry.dart';
import '../../api/models/playlist.dart';
import '../../api/models/search_result.dart';
import '../player/queue_provider.dart';
import '../search/search_controller.dart';
import '../search/search_screen.dart';
import 'playlist_card.dart';
import 'playlists_provider.dart';
import 'recent_list_controller.dart';

const _wideBreakpoint = 720.0;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeDataProvider);
    final playlistsAsync = ref.watch(playlistsProvider);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _wideBreakpoint;
          return Column(
            children: [
              if (isWide)
                const _PseudoSearchBar()
              else
                // Narrow screens: the only search entry point is a top-right
                // icon, sized and padded to sit flush with subsequent section
                // headers regardless of which sections render below.
                const _NarrowSearchRow(),
              Expanded(
                child: async.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _Empty(message: 'Failed: $e'),
                  data: (data) {
                    final top = topChannel(data.entries);
                    // Treat playlists loading/error as "no playlists" — the
                    // section only appears when we have something to show.
                    final playlists = playlistsAsync.maybeWhen(
                      data: (p) => p,
                      orElse: () => const <Playlist>[],
                    );
                    final isEmpty = data.entries.isEmpty &&
                        data.continueCard == null &&
                        top == null &&
                        playlists.isEmpty;
                    if (isEmpty) {
                      return _Empty(
                        message:
                            'Nothing here yet.\nSearch for music to get started.',
                        actionLabel: 'Search',
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(homeDataProvider);
                        ref.invalidate(playlistsProvider);
                      },
                      child: _HomeBody(
                        data: data,
                        top: top,
                        playlists: playlists,
                        ref: ref,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Centered pseudo searchbar on the home screen. Shows the live query from
/// [searchInputProvider] so it mirrors what the user typed in the search
/// dialog; tapping anywhere except the clear button opens the dialog, and
/// the X button clears the query (same effect as the X in the real field).
class _PseudoSearchBar extends ConsumerWidget {
  const _PseudoSearchBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final query = ref.watch(searchInputProvider);
    final hasText = query.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Material(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(28),
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: () => openSearch(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 6, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      size: 22,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        hasText ? query : 'Search YouTube',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (hasText)
                      InkWell(
                        borderRadius: BorderRadius.circular(11),
                        onTap: () {
                          ref.read(searchInputProvider.notifier).clear();
                          ref.read(searchQueryProvider.notifier).clear();
                        },
                        child: const SizedBox(
                          width: 22,
                          height: 22,
                          child: Icon(Icons.close, size: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Top-of-page search affordance for narrow layouts. Renders a Row with the
/// same horizontal padding, vertical padding, and label-area height as a
/// `_SectionHeader`, so the icon's vertical center lines up with the first
/// section title below regardless of which sections are present.
class _NarrowSearchRow extends StatelessWidget {
  const _NarrowSearchRow();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Expanded(child: SizedBox.shrink()),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => openSearch(context),
          ),
        ],
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({
    required this.data,
    required this.top,
    required this.playlists,
    required this.ref,
  });

  final HomeData data;
  final ({String uploader, List<HistoryEntry> tracks})? top;
  final List<Playlist> playlists;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (data.continueCard != null) {
      children.add(ContinueCardTile(card: data.continueCard!));
    }
    final topData = top;
    if (topData != null) {
      children.add(_TopChannelHeader(uploader: topData.uploader));
      final topResults = topData.tracks.map(_toSearchResult).toList();
      children.add(_GridOf(entries: topData.tracks, onTap: (i) {
        ref.read(playbackQueueProvider.notifier).playFrom(topResults, i,
            contextKind: 'channel', contextId: topData.uploader, contextTitle: topData.uploader);
      }));
    }
    if (data.entries.isNotEmpty) {
      // Search icon now lives in the top-level row above the body, so this
      // section header is purely a title — no trailing action needed.
      children.add(const _SectionHeader('Jump back in'));
      final historyResults = data.entries.map(_toSearchResult).toList();
      children.add(_ListOf(entries: data.entries, onTap: (i) {
        ref.read(playbackQueueProvider.notifier).playFrom(historyResults, i,
            contextKind: 'history');
      }));
    }
    if (playlists.isNotEmpty) {
      children.add(const _SectionHeader('Your playlists'));
      children.add(_PlaylistsRow(playlists: playlists));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24, top: 4),
      children: children,
    );
  }
}

/// "Because you listen to `uploader`" header for the top-channel section.
/// Two-line title: muted "Because you listen to" plus the uploader in bold.
class _TopChannelHeader extends StatelessWidget {
  const _TopChannelHeader({required this.uploader});
  final String uploader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Because you listen to',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            uploader,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal scroll of playlist tiles for the "Your playlists" section.
class _PlaylistsRow extends StatelessWidget {
  const _PlaylistsRow({required this.playlists});
  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: PlaylistCard.coverSize + 36, // cover + name + gap
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: playlists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final p = playlists[i];
          return PlaylistCard(
            playlist: p,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Playlist view coming soon')),
              );
            },
          );
        },
      ),
    );
  }
}

/// Plain section header — title only. Search icons live in the top header
/// row now, so this stays trivial.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

SearchResult _toSearchResult(HistoryEntry e) => SearchResult(
      id: e.videoId,
      title: e.title,
      uploader: e.uploader,
      duration: e.duration,
      thumbnail: e.thumbnail,
      type: 'video',
    );

class _ListOf extends StatelessWidget {
  const _ListOf({required this.entries, required this.onTap});
  final List<HistoryEntry> entries;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          HistoryTile(entry: entries[i], onTap: () => onTap(i)),
          const Divider(height: 1, indent: 88, endIndent: 16),
        ],
      ],
    );
  }
}

class _GridOf extends StatelessWidget {
  const _GridOf({required this.entries, required this.onTap});
  final List<HistoryEntry> entries;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 280,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.78,
        ),
        itemCount: entries.length,
        itemBuilder: (_, i) {
          return HistoryGridCard(entry: entries[i], onTap: () => onTap(i));
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message, this.actionLabel});
  final String message;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => openSearch(context),
                icon: const Icon(Icons.search),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}