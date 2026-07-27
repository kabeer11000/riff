import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/queue_provider.dart';
import 'search_controller.dart';
import 'widgets/search_result_tile.dart';

// Matches _wideBreakpoint in lib/app/app.dart — desktop opens search as a
// modal dialog instead of a full-screen page.
const _wideBreakpoint = 720.0;

/// Full-screen search page (mobile). Desktop uses [openSearch] which presents
/// the same UI inside a modal dialog instead.
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SafeArea(child: _SearchBody()));
  }
}

/// Opens search. Wide layouts get a modal dialog; narrow layouts get a pushed
/// page. Search query and field text persist across opens — they only reset
/// when the user clears with the X button.
Future<void> openSearch(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  if (width >= _wideBreakpoint) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const SizedBox(width: 600, height: 720, child: _SearchBody()),
      ),
    );
  }
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SearchScreen()));
}

class _SearchBody extends ConsumerStatefulWidget {
  const _SearchBody();

  @override
  ConsumerState<_SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends ConsumerState<_SearchBody> {
  // Controller text is seeded from the persisted [searchInputProvider] so
  // reopening search brings back whatever the user last had typed.
  late final _controller = TextEditingController(
    text: ref.read(searchInputProvider),
  );
  final _focusNode = FocusNode();
  Timer? _debounce;
  bool _showClear = false;

  @override
  void initState() {
    super.initState();
    _showClear = _controller.text.isNotEmpty;
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _showClear) {
      setState(() => _showClear = hasText);
    }
  }

  void _onChanged(String value) {
    // Persist raw text immediately so it survives teardown; debounce the
    // actual search query so we don't fire one request per keystroke.
    ref.read(searchInputProvider.notifier).set(value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(searchQueryProvider.notifier).set(value.trim());
    });
  }

  void _clear() {
    _controller.clear();
    ref.read(searchInputProvider.notifier).clear();
    ref.read(searchQueryProvider.notifier).clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(searchProvider);
    final query = ref.watch(searchQueryProvider);
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onChanged: _onChanged,
                  textInputAction: TextInputAction.search,
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: 'Search music',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: InputBorder.none,
                    suffixIcon: _showClear
                        ? IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: _clear,
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            data: (results) {
              if (query.isEmpty) {
                return const _Empty(
                  message: 'Search for songs, artists, or videos.',
                );
              }
              if (results.isEmpty) {
                return const _Empty(message: 'No results.');
              }
              return ListView.separated(
                itemCount: results.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = results[i];
                  return SearchResultTile(
                    result: r,
                    onTap: () => ref
                        .read(playbackQueueProvider.notifier)
                        .playFrom(results, i),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _Empty(message: 'Failed: $e'),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
