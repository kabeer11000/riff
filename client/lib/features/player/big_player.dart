import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ambient_lighting.dart';
import 'ambient_lighting_provider.dart';
import 'cover_video_toggle.dart';
import 'music_disk.dart';
import 'player_controller.dart';
import 'player_sheet_controller.dart';
import 'video_fullscreen_provider.dart';
import 'video_tab_provider.dart';
import 'youtube_embed.dart';

const _marqueeDuration = Duration(seconds: 8);

/// Spotify-style "About the channel" card. Round avatar (initial fallback —
/// yt-dlp doesn't surface a channel photo on video lookups), channel name,
/// dimmed subtitle, and a follow button. The follow action is a no-op for
/// now; the visual is what we want first.
class _ChannelSection extends ConsumerWidget {
  const _ChannelSection({this.padding = const EdgeInsets.symmetric(horizontal: 16)});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final uploader = state.track?.uploader ?? '';
    if (uploader.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final initial = uploader.characters.first.toUpperCase();
    // Stable color per channel so the same uploader always gets the same
    // tile background across plays.
    final seed = uploader.codeUnits.fold<int>(0, (a, c) => a + c);
    final avatarColors = [
      theme.colorScheme.primaryContainer,
      theme.colorScheme.secondaryContainer,
      theme.colorScheme.tertiaryContainer,
    ];
    final avatarColor = avatarColors[seed % avatarColors.length];
    final onAvatar = theme.colorScheme.onPrimaryContainer;
    return Padding(
      padding: padding,
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: avatarColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: onAvatar,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      uploader,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'YouTube channel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // No-op for now; just the affordance.
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                child: Text(
                  'Follow',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
      child: Stack(
        children: [
          // YouTube-style ambient lighting fills the entire player. The
          // ambient is heaviest at the top (cover area), fading to surface
          // color at the bottom so the disk/description/channel content
          // stays readable.
          _PlayerAmbientBackground(surface: theme.colorScheme.surface),
          SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                    // Settings button on the right balances the close
                    // IconButton on the left. Always accessible — not gated
                    // to video mode.
                    const _PlayerSettingsButton(),
                  ],
                ),
                // Body scrolls so the description expansion / channel card
                // never pushes content off-screen. The Draggable
                // ScrollableSheet passes its scrollController so drag and
                // scroll share an axis.
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        if (kIsWeb) ...[
                          const Center(child: CoverVideoToggle()),
                          const SizedBox(height: 12),
                        ],
                        // Cover/video card sits on top of the ambient. When
                        // fullscreen is on the embed has migrated to the
                        // overlay; render only the cover here so we don't
                        // double-mount the iframe.
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
                            onTap: () => ScaffoldMessenger.of(context)
                                .showSnackBar(
                              SnackBar(content: Text('Track: ${track.title}')),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: InkWell(
                            onTap: () =>
                                ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Artist: ${track.uploader}'),
                              ),
                            ),
                            child: Text(
                              track.uploader.isEmpty
                                  ? 'Unknown'
                                  : track.uploader,
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
                        const SizedBox(height: 24),
                        kIsWeb && ref.watch(videoTabEnabledProvider)
                            ? const SizedBox.shrink()
                            : const Center(child: MusicDisk()),
                        const SizedBox(height: 24),
                        ExpandableDescription(description: state.description),
                        const SizedBox(height: 24),
                        const _ChannelSection(),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two-layer ambient lighting for the player surfaces: the blurred cover
/// (AmbientBackdrop) sits at the back, with a vertical scrim gradient on
/// top of it that fades the ambient to panel [surface] color at the
/// bottom. Top of the player shows the cover's bleed; bottom is normal
/// surface so the disk/description/channel cards read cleanly. Used by
/// both BigPlayer and BigPlayerSidebar so the effect is consistent.
class _PlayerAmbientBackground extends StatelessWidget {
  const _PlayerAmbientBackground({required this.surface});
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Blurred cover fills the player area.
        const Positioned.fill(child: AmbientBackdrop()),
        // Vertical gradient scrim: starts darker at the top (40% surface)
        // so the cover's vivid colors are muted, then fades to full surface
        // at the bottom for readability. Without starting mid-surface the
        // ambient washes out the dark monochrome panel.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  surface.withValues(alpha: 0.4),
                  surface.withValues(alpha: 0.5),
                  surface.withValues(alpha: 0.8),
                  surface,
                ],
                stops: const [0.0, 0.35, 0.65, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Gear icon that opens the player settings menu. Currently exposes the
/// ambient lighting toggle. Sits on the right side of the modal header,
/// mirroring the close button on the left.
class _PlayerSettingsButton extends ConsumerWidget {
  const _PlayerSettingsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Player settings',
      onPressed: () => _showPlayerMenu(context, ref),
      icon: const Icon(Icons.tune),
    );
  }
}

void _showPlayerMenu(BuildContext context, WidgetRef ref) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null) return;
  final overlayBox =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlayBox == null) return;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  showMenu<void>(
    context: context,
    position: RelativeRect.fromRect(rect, Offset.zero & overlayBox.size),
    items: [
      CheckedPopupMenuItem(
        checked: ref.read(ambientLightingProvider),
        child: const Text('Ambient lighting'),
        onTap: () =>
            ref.read(ambientLightingProvider.notifier).toggle(),
      ),
    ],
  );
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

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
      ),
      // Same two-layer ambient background as the modal sheet so the
      // effect is consistent across surfaces.
      child: Stack(
        children: [
          _PlayerAmbientBackground(surface: theme.colorScheme.surface),
          SafeArea(
            top: false,
            right: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              // The sidebar column can outgrow the viewport in theater
              // mode (wide video + desc + meta). Scrollable so the user
              // can reach the description card at the bottom.
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (kIsWeb)
                      Row(
                        children: [
                          const Expanded(
                            child: Center(child: CoverVideoToggle()),
                          ),
                          // Settings button on the right so the sidebar
                          // surface has direct access to the ambient
                          // toggle without opening the modal sheet.
                          const _PlayerSettingsButton(),
                        ],
                      ),
                    if (kIsWeb) const SizedBox(height: 12),
                    // Cover/video card sits on top of the ambient. When
                    // fullscreen is on the embed has migrated to the
                    // overlay; render only the cover here.
                    if (kIsWeb &&
                        ref.watch(videoTabEnabledProvider) &&
                        !ref.watch(fullscreenVideoProvider))
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
                        onTap: () =>
                            ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Track: ${track.title}')),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: InkWell(
                        onTap: () =>
                            ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Artist: ${track.uploader}'),
                          ),
                        ),
                        child: Text(
                          track.uploader.isEmpty
                              ? 'Unknown'
                              : track.uploader,
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
                    const SizedBox(height: 16),
                    kIsWeb && ref.watch(videoTabEnabledProvider)
                        ? const SizedBox.shrink()
                        : const Center(child: MusicDisk()),
                    const SizedBox(height: 16),
                    ExpandableDescription(
                      description: state.description,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    const SizedBox(height: 16),
                    const _ChannelSection(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
