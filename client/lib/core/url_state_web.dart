import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Rewrite the query string to mirror the player. Uses `replaceState` so
/// every track change doesn't add a browser-history entry — back still
/// leaves the app, same as before URL sync existed.
void syncPlayerUrl({String? videoId, String? listId}) {
  final params = web.URLSearchParams(''.toJS);
  if (listId != null && listId.isNotEmpty) params.set('list', listId);
  if (videoId != null && videoId.isNotEmpty) params.set('v', videoId);
  final query = params.toString();
  final loc = web.window.location;
  final url = query.isEmpty ? loc.pathname : '${loc.pathname}?$query';
  web.window.history.replaceState(null, '', url);
}

({String? videoId, String? listId}) readUrlState() {
  final params = web.URLSearchParams(web.window.location.search.toJS);
  String? nonEmpty(String key) {
    final v = params.get(key);
    return (v == null || v.isEmpty) ? null : v;
  }

  return (videoId: nonEmpty('v'), listId: nonEmpty('list'));
}
