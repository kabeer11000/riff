# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

`riff` is a Flutter music app (`client/`) backed by a Go HTTP server (`riff/`). The server proxies YouTube lookups via yt-dlp, streams audio through its own `/tracks/{id}/stream` endpoint, persists play history and playlists in SQLite, and exposes a JSON API the client consumes. No auth.

## Client commands

Run from `client/`.

- Install deps: `flutter pub get`
- Run app: `flutter run` (add `-d chrome`, `-d windows`, etc. to target a device)
- Analyze/lint: `flutter analyze`
- Format: `dart format .`
- Test (all): `flutter test`
- Test (single file): `flutter test test/widget_test.dart`
- Test (single by name): `flutter test --plain-name "substring of test description"`
- Build release: `flutter build apk` / `flutter build windows` / `flutter build web`

## Backend commands

Run from `riff/`. The server is a single Go binary (`riff-server`) that depends on `yt-dlp` being on `PATH` (or set `YTDLP_PATH`).

- Build: `go build -o riff-server .`
- Run (foreground): `./riff-server`
- Run (detached, logs to `server.log`): `nohup ./riff-server >> server.log 2>&1 & disown`
- Stop: `cmd //c "taskkill /F /IM riff-server.exe"` (Windows) or `pkill riff-server` (Unix)
- Test: `curl http://localhost:8080/health` → `{"status":"ok"}`

### Config (env vars)

| Var | Default | Purpose |
|---|---|---|
| `PORT` | `8080` | HTTP listen port |
| `DB_PATH` | `riff.db` | SQLite file |
| `YTDLP_PATH` | (PATH lookup) | yt-dlp binary path |
| `CACHE_MAX_TTL` | `5m` | Ceiling for cached stream URLs |
| `CACHE_METADATA_TTL` | `1h` | Cached `GET /tracks/{id}` responses |
| `CACHE_SEARCH_TTL` | `5m` | Cached search results |

Example: `PORT=6969 ./riff-server` to run on a non-default port.

## Notes

- Dart SDK constraint: `^3.12.2` (see `client/pubspec.yaml`).
- Go route table: `riff/internal/httpapi/router.go`.
- Lints come from `flutter_lints` via `client/analysis_options.yaml`; customize rules there.
- Add client deps by editing `client/pubspec.yaml` then running `flutter pub get`.

