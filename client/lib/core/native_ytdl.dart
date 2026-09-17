import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;

/// Resolves YouTube stream URLs locally via a bundled yt-dlp on platforms
/// that can run one. This sidesteps every problem the backend fights on
/// Render: no datacenter IP flagging (this runs from the user's own IP), no
/// stream-URL IP-lock mismatch (the same machine resolves and plays), no
/// cookie relay needed. Windows only for now — Android needs different
/// packaging rules for bundling an executable.
class NativeYtdl {
  NativeYtdl._();

  static bool get isSupported => !kIsWeb && Platform.isWindows;

  static String? _binaryPath;

  /// Extracts the bundled yt-dlp.exe to a writable app-data directory on
  /// first use (Flutter assets aren't directly executable from the asset
  /// bundle). Returns the runnable path, or null if unsupported/failed.
  static Future<String?> _ensureBinary() async {
    if (!isSupported) return null;
    if (_binaryPath != null) return _binaryPath;

    final appData = Platform.environment['LOCALAPPDATA'];
    if (appData == null) return null;

    try {
      final dir = Directory('$appData\\riff\\bin');
      await dir.create(recursive: true);
      final exe = File('${dir.path}\\yt-dlp.exe');

      if (!await exe.exists() || await exe.length() == 0) {
        final data = await rootBundle.load('assets/bin/yt-dlp.exe');
        await exe.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      _binaryPath = exe.path;
      return _binaryPath;
    } catch (_) {
      return null;
    }
  }

  /// Resolves the direct, directly-playable URL for videoId's best audio
  /// format. Returns null on any failure (unsupported platform, missing
  /// binary, network error, video unavailable) so callers fall back to the
  /// backend's stream endpoint.
  static Future<String?> resolveAudioUrl(String videoId) async {
    final bin = await _ensureBinary();
    if (bin == null) return null;

    try {
      final result = await Process.run(bin, [
        '-f',
        'bestaudio',
        '-g',
        'https://www.youtube.com/watch?v=$videoId',
      ]).timeout(const Duration(seconds: 20));
      if (result.exitCode != 0) return null;

      final url = (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.startsWith('http'), orElse: () => '');
      return url.isEmpty ? null : url;
    } catch (_) {
      return null;
    }
  }
}
