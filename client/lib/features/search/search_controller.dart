import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/search.dart';
import '../../api/models/search_result.dart';
import '../../core/env.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final c = ApiClient(baseUrl: baseUrl);
  ref.onDispose(c.close);
  return c;
});

final searchApiProvider = Provider<SearchApi>((ref) => SearchApi(ref.watch(apiClientProvider)));

/// Raw text the user has typed in the search field. Lives in a provider so the
/// text survives dialog/page teardown — reopening search restores the field.
class SearchInput extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
  void clear() => state = '';
}

final searchInputProvider = NotifierProvider<SearchInput, String>(SearchInput.new);

/// Debounced query that actually drives the search request. Updating this
/// re-runs [searchProvider].
class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
  void clear() => state = '';
}

final searchQueryProvider = NotifierProvider<SearchQuery, String>(SearchQuery.new);

/// Resolved search results for the current [searchQueryProvider]. Empty query
/// short-circuits to [] so we never fire a request for blank text.
final searchProvider = FutureProvider.autoDispose<List<SearchResult>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return const [];
  final api = ref.watch(searchApiProvider);
  return api.search(query);
});