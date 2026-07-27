# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

`riff` is a Flutter music app (`client/`) backed by a Go HTTP server (`riff/`). The server proxies content lookups via yt-dlp and stores canonical, provider-agnostic items in shared Turso (libSQL). Wire formats use internal item IDs (ULID-style base32); provider-specific external IDs (YouTube today) are kept only in the `sources` table. The `recd` recommendation service reads the same Turso DB. A separate `user_id` header (`X-User-Id`) is the identity boundary — no auth yet.

API summary: `GET /search?q=` (returns indexed items with internal ids), `GET /items/{id}` (canonical), `GET /items/{id}/stream?kind=audio|muxed` (proxied audio), `GET /resolve?url=` (URL-detect + index), `GET /yt/playlists/{id}` and `GET /yt/channels/{id}` for external listings, `GET/POST/PUT/DELETE /playlists[/...]`, `GET /me/history/tracks`, `POST /me/history/tracks`. Full table in `riff/internal/httpapi/router.go`.

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

Run from `riff/`. The server is a single Go binary (`riff-server`) that depends on `yt-dlp` (set `YTDLP_PATH` or put on `PATH`).

- Build: `go build -o riff-server .`
- Run foreground (sources `.env` into the shell first): `./run.sh`
- Run detached (writes `server.log`, pid in `.server.pid`): `./run-detached.sh`
- Tail logs: `tail -f server.log`
- Stop detached: `./stop.sh`  (or `cmd //c "taskkill /F /IM riff-server.exe"`)
- Smoke: `curl http://localhost:8080/health` → `{"status":"ok"}`

### First-time setup

1. `cp .env.example .env` and fill in `TURSO_DATABASE_URL`, `TURSO_AUTH_TOKEN`, `YTDLP_PATH`.
2. `go build -o riff-server .`
3. `./run-detached.sh`

`.env`, `riff-server`, `riff-server.exe`, and `server.log` are gitignored.

### Config (env vars)

| Var | Default | Purpose |
|---|---|---|
| `PORT` | `8080` | HTTP listen port |
| `TURSO_DATABASE_URL` | _(required)_ | libSQL database URL (`libsql://...turso.io`) |
| `TURSO_AUTH_TOKEN` | _(required)_ | libSQL auth token |
| `YTDLP_PATH` | PATH lookup | yt-dlp binary path |
| `CACHE_MAX_TTL` | `5m` | Ceiling for cached resolved stream URLs (googlevideo) |
| `CACHE_METADATA_TTL` | `1h` | Cached `GET /yt/playlists/{id}` and `/yt/channels/{id}` |
| `CACHE_SEARCH_TTL` | `5m` | Cached `/search` results |
| `PUBLIC_BASE_URL` | `http://localhost:8080` | Base URL for share links |
| `REDIS_URL` | _(unused)_ | Reserved for `recd` task queue |

DB is created via `CREATE TABLE IF NOT EXISTS` on startup; no migration framework. The shared `riff.db` (legacy local SQLite) is unused and can be deleted.

## Notes

- Dart SDK constraint: `^3.12.2` (see `client/pubspec.yaml`).
- Go route table: `riff/internal/httpapi/router.go`. Domain types in `riff/internal/domain/types.go`.
- Provider abstraction: `riff/internal/provider/` (YouTube today; Spotify/MusicBrainz land behind `provider.Provider`).
- Indexer: `riff/internal/index/indexer.go`. Embed hook: `riff/internal/index/embed.go` (logs `embed:enqueue item=<id>`; will RPUSH to Redis when `recd` is wired).
- Lints come from `flutter_lints` via `client/analysis_options.yaml`; customize rules there.
- Add client deps by editing `client/pubspec.yaml` then running `flutter pub get`.
