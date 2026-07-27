// Browser URL <-> player state. Web keeps `?v=<itemId>` (and `?list=<id>`)
// in the address bar so a refresh or a shared link restores the track;
// every other platform gets no-ops.
export 'url_state_stub.dart' if (dart.library.js_interop) 'url_state_web.dart';
