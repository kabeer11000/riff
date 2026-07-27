import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Rewrite the query string to mirror the player. Uses `replaceState` so
/// every track change doesn't add a browser-history entry — back still
/// leaves the app, same as before URL sync existed. URL param `v` carries
/// an internal item id (not a YouTube id).
void syncPlayerUrl({String? itemId, String? listId}) {
  final params = web.URLSearchParams(''.toJS);
  if (listId != null && listId.isNotEmpty) params.set('list', listId);
  if (itemId != null && itemId.isNotEmpty) params.set('v', itemId);
  final query = params.toString();
  final loc = web.window.location;
  final url = query.isEmpty ? loc.pathname : '${loc.pathname}?$query';
  web.window.history.replaceState(null, '', url);
}

({String? itemId, String? listId}) readUrlState() {
  final params = web.URLSearchParams(web.window.location.search.toJS);
  String? nonEmpty(String key) {
    final v = params.get(key);
    return (v == null || v.isEmpty) ? null : v;
  }

  return (itemId: nonEmpty('v'), listId: nonEmpty('list'));
}
