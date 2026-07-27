import '../api_client.dart';
import '../models/search_result.dart';

class SearchApi {
  SearchApi(this._client);
  final ApiClient _client;

  Future<List<SearchResult>> search(String query, {int limit = 20}) async {
    final j = await _client.getJson('/search', {
      'q': query,
      'limit': '$limit',
    });
    final results = (j['results'] as List? ?? const [])
        .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
        .toList();
    return results;
  }
}