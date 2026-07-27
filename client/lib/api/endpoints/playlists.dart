import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/search/search_controller.dart' show apiClientProvider;
import '../api_client.dart';
import '../models/playlist.dart';

class PlaylistsApi {
  PlaylistsApi(this._client);
  final ApiClient _client;

  Future<List<Playlist>> list() async {
    final j = await _client.getJson('/me/playlists');
    final raw = (j['playlists'] as List?) ?? const [];
    return raw
        .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final playlistsApiProvider =
    Provider<PlaylistsApi>((ref) => PlaylistsApi(ref.watch(apiClientProvider)));