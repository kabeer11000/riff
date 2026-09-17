# Riff: production streaming + Premium-like playback

## Done
- [x] Native yt-dlp bundled for Windows audio resolution (pre-existing, committed `4bca701`)
- [x] Background audio on Android/iOS via `just_audio_background`/`audio_service` (committed `490e708`)
- [x] Search latency: cache-check-first + parallelized indexing (committed `a11a0ff`)

## In progress
- [ ] Verify whether an alternate InnerTube client context (ANDROID/IOS/etc) returns
      an unciphered, actually-fetchable stream URL today — empirical test running.
      Outcome decides whether the PHP-relay web-streaming fix is a small change or
      a much bigger signature-descrambling effort.

## Planned
- [ ] Web 403 fix: extend PHP relay (`riff/phprelay/`) to resolve real stream URLs
      for web playback, scoped by the empirical test above.
- [ ] Ad-free / native video playback on native platforms (currently web-only, via
      YouTube iframe which still shows ads). Needs raw muxed/video URL resolution
      (harder than audio-only) + a real video widget for native.
- [ ] Settings option in native apps (Windows now, Android/iOS once they get a
      native resolver) to check for and update the bundled yt-dlp binary — so
      users aren't stuck on the version shipped with the app build when YouTube
      changes break an old yt-dlp. Needs: version-check endpoint or GitHub
      releases API call, download + atomic replace of the binary in
      `%LOCALAPPDATA%\riff\bin\yt-dlp.exe` (mirrors `native_ytdl.dart`'s existing
      extract-on-first-use logic), and a Settings UI entry with current
      version + "Check for update"/"Update" action.
