import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cover_video_toggle.dart';
import 'music_disk.dart';
import 'player_controller.dart';
import 'player_sheet_controller.dart';
import 'video_fullscreen_provider.dart';
import 'video_tab_provider.dart';
import 'youtube_embed.dart';

const _marqueeDuration = Duration(seconds: 8);

/// Single dimmed line showing whatever optional metadata we have for the
/// current track. Joins available fields with ` • `. Returns nothing when no
/// metadata is available so the description below has the space to itself.
class _TrackMetaLine extends StatelessWidget {
  const _TrackMetaLine({
    required this.artist,
    required this.album,
    required this.releaseYear,
    required this.viewCount,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final String artist;
  final String album;
  final int? releaseYear;
  final double viewCount;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (artist.isNotEmpty) parts.add(artist);
    if (album.isNotEmpty) parts.add(album);
    if (releaseYear != null) parts.add('$releaseYear');
    if (viewCount > 0) parts.add(_formatViews(viewCount));
    if (parts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(
        parts.join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  // Compact view count: 1234 -> 1.2K, 1_500_000 -> 1.5M.
  static String _formatViews(double v) {
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}B views';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M views';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K views';
    return '${v.toStringAsFixed(0)} views';
  }
}

class ExpandableDescription extends StatefulWidget {
  const ExpandableDescription({
    super.key,
    required this.description,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final String description;
  final EdgeInsetsGeometry padding;

  @override
  State<ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<ExpandableDescription> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.description.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: widget.padding,
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Description',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: Text(
                    widget.description,
                    maxLines: _expanded ? null : 3,
                    overflow: _expanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _expanded ? 'Show less' : 'Show more',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tag used by both the miniplayer and the big-player cover so the Hero
/// morph animates the cover from the bottom-right mini into the big player.
String playerCoverHeroTag(String videoId) => 'player-cover-$videoId';

/// Open the big-player sheet at full screen. Snap points: [dismiss=0, full=100%].
/// Drag-up/down snaps between them; dragging past the midpoint dismisses.
/// The `DraggableScrollableController` listens for the sheet to fully collapse
/// and pops the route, so the user can dismiss without the close button.
Future<void> showPlayerSheet(BuildContext context) {
  final container = ProviderScope.containerOf(context);
  final navigator = Navigator.of(context);
  container.read(playerSheetControllerProvider.notifier).open();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: false, // DraggableScrollableSheet owns the drag
    constraints: const BoxConstraints(maxWidth: double.infinity),
    builder: (_) {
      final sheetController = DraggableScrollableController();
      sheetController.addListener(() {
        if (!sheetController.isAttached) return;
        if (sheetController.size < 0.05 && navigator.canPop()) {
          navigator.pop();
        }
      });
      return DraggableScrollableSheet(
        controller: sheetController,
        initialChildSize: 1.0,
        minChildSize: 0.0,
        maxChildSize: 1.0,
        snap: true,
        snapSizes: const [0.0, 1.0],
        builder: (context, scrollController) =>
            BigPlayer(scrollController: scrollController),
      );
    },
  ).whenComplete(() {
    container.read(playerSheetControllerProvider.notifier).close();
  });
}

class BigPlayer extends ConsumerWidget {
  const BigPlayer({super.key, this.scrollController});
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    ref.listen<PlayerState>(playerControllerProvider, (prev, next) {
      if (next.track == null && prev?.track != null) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    });
    final track = state.track;
    if (track == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isFullscreen = ref.watch(fullscreenVideoProvider);

    return Container(
      decoration: BoxDecoration(color: theme.colorScheme.surface),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _DragHandleVisual(),
            Row(
              children: [
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Now playing',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 8),
            if (kIsWeb) ...[
              const Center(child: CoverVideoToggle()),
              const SizedBox(height: 12),
            ],
            // When fullscreen is on the embed has migrated to the overlay;
            // render only the cover here so we don't double-mount the iframe.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: kIsWeb &&
                      ref.watch(videoTabEnabledProvider) &&
                      !isFullscreen
                  ? YouTubeEmbed(videoId: track.id)
                  : const CoverArt(),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _Marquee(
                text: track.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Track: ${track.title}')),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InkWell(
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Artist: ${track.uploader}')),
                ),
                child: Text(
                  track.uploader.isEmpty ? 'Unknown' : track.uploader,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            _TrackMetaLine(
              artist: state.artist,
              album: state.album,
              releaseYear: state.releaseYear,
              viewCount: state.viewCount,
            ),
            const SizedBox(height: 12),
            ExpandableDescription(description: state.description),
            const SizedBox(height: 32),
            kIsWeb && ref.watch(videoTabEnabledProvider)
                ? const SizedBox.shrink()
                : const Center(child: MusicDisk()),
            const Spacer(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _DragHandleVisual extends StatelessWidget {
  const _DragHandleVisual();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Permanent right-side panel for the big player on wide layouts. Reuses
/// the same content widgets as the bottom-sheet version (cover, title,
/// uploader, disk) but without a drag handle or close button — the panel
/// stays open while a track is loaded and collapses to nothing when the
/// queue empties.
class BigPlayerSidebar extends ConsumerWidget {
  const BigPlayerSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final track = state.track;
    if (track == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isFullscreen = ref.watch(fullscreenVideoProvider);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
      ),
      child: SafeArea(
        top: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          // Non-scrolling scroll view: in theater mode the wide video makes
          // the column taller than the viewport; this clips the overflow
          // (cutting the disk) instead of throwing a RenderFlex overflow.
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kIsWeb) ...[
                  const Center(child: CoverVideoToggle()),
                  const SizedBox(height: 12),
                ],
                if (kIsWeb &&
                    ref.watch(videoTabEnabledProvider) &&
                    !isFullscreen)
                  YouTubeEmbed(
                    videoId: track.id,
                    showTheater: true,
                  )
                else
                  const CoverArt(),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _Marquee(
                    text: track.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Track: ${track.title}')),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: InkWell(
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Artist: ${track.uploader}')),
                    ),
                    child: Text(
                      track.uploader.isEmpty ? 'Unknown' : track.uploader,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _TrackMetaLine(
                  artist: state.artist,
                  album: state.album,
                  releaseYear: state.releaseYear,
                  viewCount: state.viewCount,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                const SizedBox(height: 12),
                ExpandableDescription(
                  description: state.description,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                const SizedBox(height: 32),
                kIsWeb && ref.watch(videoTabEnabledProvider)
                    ? const SizedBox.shrink()
                    : const Center(child: MusicDisk()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Single-line text that auto-scrolls horizontally when it overflows the
/// available width. Tapping fires [onTap] (the rest of the player treats
/// the title as a clickable affordance). When the text fits, it shows
/// normally with no animation.
class _Marquee extends StatefulWidget {
  const _Marquee({required this.text, this.style, this.onTap});

  final String text;
  final TextStyle? style;
  final VoidCallback? onTap;

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  late final AnimationController _animController;
  bool _overflows = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: _marqueeDuration,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void didUpdateWidget(_Marquee old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _animController.stop();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
    }
  }

  void _checkOverflow() {
    if (!mounted || !_scrollController.hasClients) return;
    final overflow = _scrollController.position.maxScrollExtent > 0;
    if (overflow != _overflows) {
      setState(() => _overflows = overflow);
      if (overflow) {
        _animController.repeat();
      } else {
        _animController.stop();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_overflows) {
      return InkWell(
        onTap: widget.onTap,
        child: Text(
          widget.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: widget.style,
        ),
      );
    }
    return InkWell(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (_, child) {
          if (_scrollController.hasClients) {
            final max = _scrollController.position.maxScrollExtent;
            _scrollController.jumpTo(max * _animController.value);
          }
          return child!;
        },
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Text(widget.text, maxLines: 1, style: widget.style),
        ),
      ),
    );
  }
}
