import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'video_tab_provider.dart';

/// Pill switching the big player's main slot between cover art, the YouTube
/// embed, and the queue. The Video segment is web-only — non-streamable
/// items (no YouTube source) leave the embed empty.
class CoverVideoToggle extends ConsumerWidget {
  const CoverVideoToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tab = ref.watch(playerTabProvider);
    void select(PlayerTab t) => ref.read(playerTabProvider.notifier).set(t);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            label: 'Cover',
            selected: tab == PlayerTab.cover,
            onTap: () => select(PlayerTab.cover),
          ),
          if (kIsWeb)
            _Segment(
              label: 'Video',
              selected: tab == PlayerTab.video,
              onTap: () => select(PlayerTab.video),
            ),
          _Segment(
            label: 'Queue',
            selected: tab == PlayerTab.queue,
            onTap: () => select(PlayerTab.queue),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
