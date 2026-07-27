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
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
        ),
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
