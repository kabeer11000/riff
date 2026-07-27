import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/home/home_screen.dart';
import '../features/library/library_sidebar.dart';
import '../features/player/big_player.dart';
import '../features/player/mini_player.dart';
import '../features/player/player_controller.dart';
import '../features/player/player_sheet_controller.dart';
import '../features/player/video_fullscreen_provider.dart';
import '../features/player/video_tab_provider.dart';
import '../features/player/youtube_embed.dart';
import '../api/models/search_result.dart';
import 'theme.dart';

// Below this: mobile (home + bottom miniplayer). Between this and
// _desktopBreakpoint: wide (home + big-player sidebar). At/above
// _desktopBreakpoint: full three-pane desktop (library + home + player).
const _wideBreakpoint = 720.0;
const _desktopBreakpoint = 1024.0;
const _librarySidebarWidth = 300.0;
const _playerSidebarWidth = 400.0;
const _theaterAnim = Duration(milliseconds: 280);
const _theaterCurve = Curves.easeInOutCubic;

class RiffApp extends StatelessWidget {
  const RiffApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Riff',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _HomeShell(),
    );
  }
}

class _HomeShell extends ConsumerWidget {
  const _HomeShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Auto-open the big-player sheet on mobile whenever a new track starts.
    // The desktop sidebar is already driven by hasTrack below.
    ref.listen<PlayerState>(playerControllerProvider, (prev, next) {
      final prevId = prev?.track?.id;
      final nextId = next.track?.id;
      if (nextId == null || nextId == prevId) return;
      final width = MediaQuery.of(context).size.width;
      if (width >= _wideBreakpoint) return;
      final sheetMode = ref.read(playerSheetControllerProvider).mode;
      if (sheetMode == PlayerSheetMode.hidden) {
        showPlayerSheet(context);
      }
    });

    final hasTrack = ref.watch(
      playerControllerProvider.select((s) => s.track != null),
    );
    // Theater mode only bites while the video tab is active on a wide layout.
    final theater = ref.watch(theaterModeProvider) &&
        ref.watch(videoTabEnabledProvider);
    final fullscreen = ref.watch(fullscreenVideoProvider);
    final track = ref.watch(playerControllerProvider.select((s) => s.track));

    return Scaffold(
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final playerWidth =
                  theater ? width * 0.72 : _playerSidebarWidth;
              if (width >= _desktopBreakpoint) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Collapses to 0 in theater mode. The child stays a fixed
                    // width and is clipped, so its contents never overflow while
                    // the container animates shut.
                    AnimatedContainer(
                      duration: _theaterAnim,
                      curve: _theaterCurve,
                      width: theater ? 0 : _librarySidebarWidth,
                      child: ClipRect(
                        child: OverflowBox(
                          minWidth: _librarySidebarWidth,
                          maxWidth: _librarySidebarWidth,
                          alignment: Alignment.centerLeft,
                          child: const SizedBox(
                            width: _librarySidebarWidth,
                            child: LibrarySidebar(),
                          ),
                        ),
                      ),
                    ),
                    const Expanded(child: HomeScreen()),
                    if (hasTrack)
                      AnimatedContainer(
                        duration: _theaterAnim,
                        curve: _theaterCurve,
                        width: playerWidth,
                        child: const BigPlayerSidebar(),
                      ),
                  ],
                );
              }
              if (width >= _wideBreakpoint) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Expanded(child: HomeScreen()),
                    if (hasTrack)
                      AnimatedContainer(
                        duration: _theaterAnim,
                        curve: _theaterCurve,
                        width: playerWidth,
                        child: const BigPlayerSidebar(),
                      ),
                  ],
                );
              }
              return Stack(
                children: const [
                  Positioned.fill(child: HomeScreen()),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: MiniPlayer(),
                  ),
                ],
              );
            },
          ),
          // Full-window overlay rendered above the layout when fullscreen is
          // active. Only mounts the iframe when there's something to play; the
          // inline embeds in BigPlayer/BigPlayerSidebar are responsible for
          // hiding themselves when this is true (so we never have two iframes).
          if (fullscreen && track != null)
            Positioned.fill(child: _FullscreenVideoOverlay(track: track)),
        ],
      ),
    );
  }
}

/// Full-window route-style surface for the YouTube embed. Uses a black
/// backdrop so the iframe fills the whole viewport regardless of theme.
class _FullscreenVideoOverlay extends StatelessWidget {
  const _FullscreenVideoOverlay({required this.track});
  final SearchResult track;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: YouTubeEmbed(
          videoId: track.id,
          fullscreen: true,
        ),
      ),
    );
  }
}
