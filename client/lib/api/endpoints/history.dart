import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/search/search_controller.dart' show apiClientProvider;
import '../api_client.dart';
import '../models/continue_card.dart';
import '../models/history_entry.dart';

class HistoryApi {
  HistoryApi(this._client);
  final ApiClient _client;

  /// Returns the home data payload. Server groups plays per item and pairs
  /// the list with the latest playlist/channel continue card in one round-trip.
  Future<({List<HistoryEntry> entries, ContinueCard? continueCard})> list({
    int limit = 20,
  }) async {
    final j = await _client.getJson('/me/history/tracks', {'limit': '$limit'});
    final entries = ((j['entries'] as List?) ?? const [])
        .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    final raw = j['continue'];
    final card = raw is Map<String, dynamic>
        ? ContinueCard.fromJson(raw)
        : null;
    return (entries: entries, continueCard: card);
  }

  /// Fire-and-forget POST. Best-effort: callers don't await and don't surface
  /// failures to the user — losing a position tick is acceptable.
  Future<void> record({
    required String itemId,
    required String title,
    String uploader = '',
    double duration = 0,
    String thumbnail = '',
    double position = 0,
    String contextKind = '',
    String contextId = '',
    String contextTitle = '',
  }) {
    final body = <String, dynamic>{
      'itemId': itemId,
      'title': title,
      if (uploader.isNotEmpty) 'uploader': uploader,
      if (duration > 0) 'duration': duration,
      if (thumbnail.isNotEmpty) 'thumbnail': thumbnail,
      if (position > 0) 'position': position,
      if (contextKind.isNotEmpty) 'contextKind': contextKind,
      if (contextId.isNotEmpty) 'contextId': contextId,
      if (contextTitle.isNotEmpty) 'contextTitle': contextTitle,
    };
    return _client.postJson('/me/history/tracks', body);
  }

  Future<void> deleteTrack(String itemId) =>
      _client.delete('/me/history/tracks/$itemId');

  Future<void> clear() => _client.delete('/me/history/tracks');
}

final historyApiProvider = Provider<HistoryApi>(
  (ref) => HistoryApi(ref.watch(apiClientProvider)),
);
