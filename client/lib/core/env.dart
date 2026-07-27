import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

const _defaultBaseUrl = 'http://localhost:8080';

/// Base URL of the riff backend. Overridable via --dart-define=API_BASE_URL=...
/// so a phone on the LAN can hit a dev box. Per-platform defaults cover the
/// common dev cases (Android emulator uses 10.0.2.2 for the host loopback).
String get baseUrl {
  const fromDefine = String.fromEnvironment('API_BASE_URL');
  if (fromDefine.isNotEmpty) return fromDefine;
  if (kIsWeb) return _defaultBaseUrl;
  if (Platform.isAndroid) return 'http://10.0.2.2:8080';
  return _defaultBaseUrl;
}
