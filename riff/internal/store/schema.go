package store

const schema = `
CREATE TABLE IF NOT EXISTS users (
	id           TEXT PRIMARY KEY,
	display_name TEXT NOT NULL DEFAULT '',
	avatar_url   TEXT NOT NULL DEFAULT '',
	created_at   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS playlists (
	id          TEXT PRIMARY KEY,
	owner_id    TEXT NOT NULL,
	name        TEXT NOT NULL,
	description TEXT NOT NULL DEFAULT '',
	cover_url   TEXT NOT NULL DEFAULT '',
	visibility  TEXT NOT NULL DEFAULT 'private'
		CHECK (visibility IN ('public','private','unlisted')),
	share_token TEXT UNIQUE,
	created_at  TEXT NOT NULL,
	updated_at  TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_playlists_owner ON playlists(owner_id);

CREATE TABLE IF NOT EXISTS playlist_tracks (
	playlist_id TEXT NOT NULL,
	video_id    TEXT NOT NULL,
	position    INTEGER NOT NULL,
	title       TEXT NOT NULL DEFAULT '',
	uploader    TEXT NOT NULL DEFAULT '',
	duration    REAL NOT NULL DEFAULT 0,
	thumbnail   TEXT NOT NULL DEFAULT '',
	added_by    TEXT NOT NULL DEFAULT '',
	added_at    TEXT NOT NULL,
	PRIMARY KEY (playlist_id, video_id)
);

CREATE TABLE IF NOT EXISTS liked_tracks (
	user_id   TEXT NOT NULL,
	video_id  TEXT NOT NULL,
	title     TEXT NOT NULL DEFAULT '',
	uploader  TEXT NOT NULL DEFAULT '',
	duration  REAL NOT NULL DEFAULT 0,
	thumbnail TEXT NOT NULL DEFAULT '',
	liked_at  TEXT NOT NULL,
	PRIMARY KEY (user_id, video_id)
);

CREATE TABLE IF NOT EXISTS saved_playlists (
	user_id     TEXT NOT NULL,
	playlist_id TEXT NOT NULL,
	saved_at    TEXT NOT NULL,
	PRIMARY KEY (user_id, playlist_id)
);

CREATE TABLE IF NOT EXISTS listening_history (
	id            INTEGER PRIMARY KEY AUTOINCREMENT,
	user_id       TEXT NOT NULL,
	video_id      TEXT NOT NULL,
	title         TEXT NOT NULL DEFAULT '',
	uploader      TEXT NOT NULL DEFAULT '',
	duration      REAL NOT NULL DEFAULT 0,
	thumbnail     TEXT NOT NULL DEFAULT '',
	played_at     TEXT NOT NULL,
	last_position REAL NOT NULL DEFAULT 0,
	context_kind  TEXT NOT NULL DEFAULT '',
	context_id    TEXT NOT NULL DEFAULT '',
	context_title TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_history_user_recent
	ON listening_history(user_id, played_at DESC);
CREATE INDEX IF NOT EXISTS idx_history_user_video
	ON listening_history(user_id, video_id, played_at DESC);
`
