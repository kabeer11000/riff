import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/endpoints/playlists.dart';
import '../../api/models/playlist.dart';

/// The signed-in user's own Riff playlists. Fed by /me/playlists; only the
/// fields surfaced on the home screen tile (id, name, cover, visibility) are
/// deserialized — the listing endpoint doesn't include track metadata.
final playlistsProvider = FutureProvider.autoDispose<List<Playlist>>((ref) async {
  return ref.read(playlistsApiProvider).list();
});