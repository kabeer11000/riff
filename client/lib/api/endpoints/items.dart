import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/search/search_controller.dart' show apiClientProvider;
import '../api_client.dart';
import '../models/item.dart';

class ItemsApi {
  ItemsApi(this._client);
  final ApiClient _client;

  /// Fetch the canonical item (with sources[]). Throws on 404 — callers that
  /// want optional behavior should catch and skip.
  Future<Item> get(String itemId) async {
    final j = await _client.getJson('/items/$itemId');
    return Item.fromJson(j);
  }

  /// URL the audio player streams from. The backend proxies bytes, so the
  /// client's IP never hits Google directly.
  String streamUrl(String itemId, {String kind = 'audio'}) =>
      '${_client.baseUrl}/items/$itemId/stream?kind=$kind';
}

final itemsApiProvider = Provider<ItemsApi>(
  (ref) => ItemsApi(ref.watch(apiClientProvider)),
);
