import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ambient_lighting.dart';
import 'ambient_lighting_provider.dart';
import 'cover_video_toggle.dart';
import 'music_disk.dart';
import 'player_controller.dart';
import 'player_sheet_controller.dart';
import 'provider_metadata_section.dart';
import 'queue_panel.dart';
import 'video_fullscreen_provider.dart';
import 'video_tab_provider.dart';
import 'youtube_embed.dart';

const _marqueeDuration = Duration(seconds: 8);

/// Spotify-style "About the channel" card. Round avatar (initial fallback —
/// yt-dlp doesn't surface a channel photo on video lookups), channel name,
/// dimmed subtitle, and a follow button. The follow action is a no-op for
/// now; the visual is what we want first.
class _ProviderMeta extends ConsumerWidget {
  const _ProviderMeta({
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(playerControllerProvider.select((s) => s.item));
    if (item == null) return const SizedBox.shrink();
    return ProviderMetadataSection(item: item, padding: padding);
  }
}

/// Tag used by both the miniplayer and the big-player cover so the Hero
/// morph animates the cover from the bottom-right mini into the big player.
String playerCoverHeroTag(String itemId) => 'player-cover-$itemId';

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
                        const Center(child: CoverVideoToggle()),
                        const SizedBox(height: 12),
                        // Cover / video / queue slot sits on top of the
                        // ambient. When fullscreen is on, the embed has
                        // migrated to the overlay so we render the cover
                        // instead — never two iframes at once.
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: switch (ref.watch(playerTabProvider)) {
                            PlayerTab.queue => const QueuePanel(),
                            PlayerTab.video
                                when kIsWeb &&
                                    !isFullscreen &&
                                    state.item != null =>
                              YouTubeEmbed(item: state.item!),
                            _ => const CoverArt(),
                          },
                        ),
                        if (ref.watch(playerTabProvider) !=
                            PlayerTab.queue) ...[
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _Marquee(
                              text: track.title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              onTap: () =>
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Track: ${track.title}'),
                                    ),
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
                                      content: Text(
                                        'Artist: ${track.uploader}',
                                      ),
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
                          const SizedBox(height: 24),
                          kIsWeb && ref.watch(videoTabEnabledProvider)
                              ? const SizedBox.shrink()
                              : const Center(child: MusicDisk()),
                          const SizedBox(height: 24),
                          const _ProviderMeta(),
                        ],
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
        onTap: () => ref.read(ambientLightingProvider.notifier).toggle(),
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
      decoration: BoxDecoration(color: theme.colorScheme.surface),
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
                    const SizedBox(height: 12),
                    // Cover / video / queue slot sits on top of the
                    // ambient. When fullscreen is on, the embed has
                    // migrated to the overlay so we render the cover
                    // instead.
                    switch (ref.watch(playerTabProvider)) {
                      PlayerTab.queue => const QueuePanel(),
                      PlayerTab.video
                          when kIsWeb &&
                              !ref.watch(fullscreenVideoProvider) &&
                              state.item != null =>
                        YouTubeEmbed(item: state.item!, showTheater: true),
                      _ => const CoverArt(),
                    },
                    if (ref.watch(playerTabProvider) != PlayerTab.queue) ...[
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
                                SnackBar(
                                  content: Text('Track: ${track.title}'),
                                ),
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
                      const SizedBox(height: 16),
                      kIsWeb && ref.watch(videoTabEnabledProvider)
                          ? const SizedBox.shrink()
                          : const Center(child: MusicDisk()),
                      const SizedBox(height: 16),
                      const _ProviderMeta(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ],
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
