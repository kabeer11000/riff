# Riff: production streaming + Premium-like playback

## Done
- [x] Native yt-dlp bundled for Windows audio resolution (pre-existing, committed `4bca701`)
- [x] Background audio on Android/iOS via `just_audio_background`/`audio_service` (committed `490e708`)
- [x] Search latency: cache-check-first + parallelized indexing (committed `a11a0ff`)
- [x] Production 403 fix: stream resolution now goes through the PHP relay's ANDROID
      InnerTube client context, which returns unciphered URLs the proxy-pool/yt-dlp
      path never reliably could (committed `1b394c5`, live on Render with
      `SCRAPER_BACKEND=php`). Verified in production logs: a URL resolved by
      InfinityFree's IP was fetched by Render's (different) IP and returned 206 —
      confirms the ANDROID client's URLs aren't IP-locked the way WEB's are.
      Caveat: yt-dlp's own source flags a `GVS_PO_TOKEN_POLICY` on this client that
      YouTube could start enforcing at any time, which would break this again —
      not a permanent fix, watch for renewed 403s.

## Planned
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
