import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Toggle for the YouTube-style ambient lighting glow around the video
/// embed. When on, a heavily-blurred thumbnail is rendered behind the
/// iframe so the video appears to bleed into the surrounding panel.
class AmbientLighting extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool v) => state = v;
  void toggle() => state = !state;
}

final ambientLightingProvider = NotifierProvider<AmbientLighting, bool>(
  AmbientLighting.new,
);
