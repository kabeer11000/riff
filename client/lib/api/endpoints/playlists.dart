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

  Future<void> addTrack(
    String playlistId,
    String itemId, {
    String title = '',
    String uploader = '',
    double duration = 0,
    String thumbnail = '',
  }) {
    final body = <String, dynamic>{
      'itemId': itemId,
      if (title.isNotEmpty) 'title': title,
      if (uploader.isNotEmpty) 'uploader': uploader,
      if (duration > 0) 'duration': duration,
      if (thumbnail.isNotEmpty) 'thumbnail': thumbnail,
    };
    return _client.postJson('/playlists/$playlistId/tracks', body);
  }
}

final playlistsApiProvider = Provider<PlaylistsApi>(
  (ref) => PlaylistsApi(ref.watch(apiClientProvider)),
);
