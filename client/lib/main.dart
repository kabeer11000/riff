import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // Our own track menu handles right-click; the browser's menu would
    // otherwise open on top of it.
    await BrowserContextMenu.disableContextMenu();
  }
  // Lock-screen/notification controls + survives backgrounding on mobile.
  // Desktop (Windows) keeps running when minimized regardless, and
  // audio_service doesn't support it, so skip there.
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'network.kabeers.riffmusic.riff.audio',
      androidNotificationChannelName: 'Riff playback',
      androidNotificationOngoing: true,
    );
  }
  runApp(const ProviderScope(child: RiffApp()));
}
