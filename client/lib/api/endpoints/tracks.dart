import '../api_client.dart';
import '../models/track_info.dart';

class TracksApi {
  TracksApi(this._client);
  final ApiClient _client;

  Future<TrackInfo> get(String videoId) async {
    final j = await _client.getJson('/tracks/$videoId');
    return TrackInfo.fromJson(j);
  }

  /// URL the audio player streams from. The backend proxies the bytes, so the
  /// client's IP never hits Google directly.
  String streamUrl(String videoId, {String kind = 'audio'}) =>
      '${_client.baseUrl}/tracks/$videoId/stream?kind=$kind';
}