package store

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/base32"
	"errors"
	"time"

	_ "modernc.org/sqlite"

	"riff/m/internal/domain"
)

// SQLite is the modernc.org/sqlite-backed Repository implementation.
type SQLite struct {
	db *sql.DB
}

func OpenSQLite(path string) (*SQLite, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	// modernc sqlite is single-connection-friendly; cap to avoid "database is locked".
	db.SetMaxOpenConns(1)
	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, err
	}
	return &SQLite{db: db}, nil
}

func (s *SQLite) Close() error { return s.db.Close() }

func newID() string {
	b := make([]byte, 10)
	_, _ = rand.Read(b)
	return base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(b)
}

func now() string { return time.Now().UTC().Format(time.RFC3339Nano) }

func parseTime(s string) time.Time {
	t, _ := time.Parse(time.RFC3339Nano, s)
	return t
}

// --- users ---

func (s *SQLite) EnsureUser(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO users (id, created_at) VALUES (?, ?) ON CONFLICT(id) DO NOTHING`,
		id, now())
	return err
}

func (s *SQLite) GetProfile(ctx context.Context, id string) (domain.Profile, error) {
	var p domain.Profile
	var created string
	err := s.db.QueryRowContext(ctx,
		`SELECT id, display_name, avatar_url, created_at FROM users WHERE id = ?`, id).
		Scan(&p.ID, &p.DisplayName, &p.AvatarURL, &created)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Profile{}, ErrNotFound
	}
	if err != nil {
		return domain.Profile{}, err
	}
	p.CreatedAt = parseTime(created)
	return p, nil
}

func (s *SQLite) UpdateProfile(ctx context.Context, id, displayName, avatarURL string) (domain.Profile, error) {
	_, err := s.db.ExecContext(ctx,
		`UPDATE users SET display_name = ?, avatar_url = ? WHERE id = ?`,
		displayName, avatarURL, id)
	if err != nil {
		return domain.Profile{}, err
	}
	return s.GetProfile(ctx, id)
}

// --- playlists ---

func (s *SQLite) ownerOf(ctx context.Context, playlistID string) (string, error) {
	var owner string
	err := s.db.QueryRowContext(ctx,
		`SELECT owner_id FROM playlists WHERE id = ?`, playlistID).Scan(&owner)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrNotFound
	}
	return owner, err
}

func (s *SQLite) assertOwner(ctx context.Context, playlistID, ownerID string) error {
	owner, err := s.ownerOf(ctx, playlistID)
	if err != nil {
		return err
	}
	if owner != ownerID {
		return ErrForbidden
	}
	return nil
}

func (s *SQLite) CreatePlaylist(ctx context.Context, ownerID, name, description, visibility string) (domain.Playlist, error) {
	if visibility == "" {
		visibility = domain.VisibilityPrivate
	}
	id := newID()
	ts := now()
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO playlists (id, owner_id, name, description, visibility, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		id, ownerID, name, description, visibility, ts, ts)
	if err != nil {
		return domain.Playlist{}, err
	}
	return s.GetPlaylist(ctx, id)
}

func (s *SQLite) GetPlaylist(ctx context.Context, id string) (domain.Playlist, error) {
	p, err := s.scanPlaylist(ctx, `SELECT id, owner_id, name, description, cover_url, visibility,
		COALESCE(share_token,''), created_at, updated_at FROM playlists WHERE id = ?`, id)
	if err != nil {
		return domain.Playlist{}, err
	}
	tracks, err := s.playlistTracks(ctx, p.ID)
	if err != nil {
		return domain.Playlist{}, err
	}
	p.Tracks = tracks
	return p, nil
}

func (s *SQLite) GetPlaylistByShareToken(ctx context.Context, token string) (domain.Playlist, error) {
	p, err := s.scanPlaylist(ctx, `SELECT id, owner_id, name, description, cover_url, visibility,
		COALESCE(share_token,''), created_at, updated_at FROM playlists WHERE share_token = ?`, token)
	if err != nil {
		return domain.Playlist{}, err
	}
	tracks, err := s.playlistTracks(ctx, p.ID)
	if err != nil {
		return domain.Playlist{}, err
	}
	p.Tracks = tracks
	return p, nil
}

func (s *SQLite) scanPlaylist(ctx context.Context, query, arg string) (domain.Playlist, error) {
	var p domain.Playlist
	var created, updated string
	err := s.db.QueryRowContext(ctx, query, arg).Scan(
		&p.ID, &p.OwnerID, &p.Name, &p.Description, &p.CoverURL, &p.Visibility,
		&p.ShareToken, &created, &updated)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Playlist{}, ErrNotFound
	}
	if err != nil {
		return domain.Playlist{}, err
	}
	p.CreatedAt = parseTime(created)
	p.UpdatedAt = parseTime(updated)
	return p, nil
}

func (s *SQLite) playlistTracks(ctx context.Context, playlistID string) ([]domain.PlaylistTrack, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT video_id, position, title, uploader, duration, thumbnail, added_at
		 FROM playlist_tracks WHERE playlist_id = ? ORDER BY position ASC`, playlistID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	tracks := []domain.PlaylistTrack{}
	for rows.Next() {
		var t domain.PlaylistTrack
		var added string
		if err := rows.Scan(&t.VideoID, &t.Position, &t.Title, &t.Uploader, &t.Duration, &t.Thumbnail, &added); err != nil {
			return nil, err
		}
		t.AddedAt = parseTime(added)
		tracks = append(tracks, t)
	}
	return tracks, rows.Err()
}

// listPlaylists returns playlist metadata only (no tracks) to avoid N+1 on listings.
func (s *SQLite) listPlaylists(ctx context.Context, query string, args ...any) ([]domain.Playlist, error) {
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.Playlist{}
	for rows.Next() {
		var p domain.Playlist
		var created, updated string
		if err := rows.Scan(&p.ID, &p.OwnerID, &p.Name, &p.Description, &p.CoverURL,
			&p.Visibility, &p.ShareToken, &created, &updated); err != nil {
			return nil, err
		}
		p.CreatedAt = parseTime(created)
		p.UpdatedAt = parseTime(updated)
		out = append(out, p)
	}
	return out, rows.Err()
}

func (s *SQLite) ListPlaylistsByOwner(ctx context.Context, ownerID string, onlyPublic bool) ([]domain.Playlist, error) {
	q := `SELECT id, owner_id, name, description, cover_url, visibility,
		COALESCE(share_token,''), created_at, updated_at FROM playlists WHERE owner_id = ?`
	if onlyPublic {
		q += ` AND visibility = 'public'`
	}
	q += ` ORDER BY updated_at DESC`
	return s.listPlaylists(ctx, q, ownerID)
}

func (s *SQLite) UpdatePlaylist(ctx context.Context, id, ownerID, name, description, coverURL, visibility string) (domain.Playlist, error) {
	if err := s.assertOwner(ctx, id, ownerID); err != nil {
		return domain.Playlist{}, err
	}
	_, err := s.db.ExecContext(ctx,
		`UPDATE playlists SET name = ?, description = ?, cover_url = ?, visibility = ?, updated_at = ?
		 WHERE id = ?`,
		name, description, coverURL, visibility, now(), id)
	if err != nil {
		return domain.Playlist{}, err
	}
	return s.GetPlaylist(ctx, id)
}

func (s *SQLite) DeletePlaylist(ctx context.Context, id, ownerID string) error {
	if err := s.assertOwner(ctx, id, ownerID); err != nil {
		return err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `DELETE FROM playlist_tracks WHERE playlist_id = ?`, id); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM saved_playlists WHERE playlist_id = ?`, id); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM playlists WHERE id = ?`, id); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *SQLite) SetShareToken(ctx context.Context, id, ownerID, token string) (domain.Playlist, error) {
	if err := s.assertOwner(ctx, id, ownerID); err != nil {
		return domain.Playlist{}, err
	}
	_, err := s.db.ExecContext(ctx,
		`UPDATE playlists SET share_token = ?, updated_at = ? WHERE id = ?`, token, now(), id)
	if err != nil {
		return domain.Playlist{}, err
	}
	return s.GetPlaylist(ctx, id)
}

// --- playlist tracks ---

func (s *SQLite) AddPlaylistTrack(ctx context.Context, playlistID, ownerID string, t domain.PlaylistTrack) error {
	if err := s.assertOwner(ctx, playlistID, ownerID); err != nil {
		return err
	}
	var next int
	err := s.db.QueryRowContext(ctx,
		`SELECT COALESCE(MAX(position)+1, 0) FROM playlist_tracks WHERE playlist_id = ?`, playlistID).
		Scan(&next)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx,
		`INSERT INTO playlist_tracks (playlist_id, video_id, position, title, uploader, duration, thumbnail, added_by, added_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(playlist_id, video_id) DO NOTHING`,
		playlistID, t.VideoID, next, t.Title, t.Uploader, t.Duration, t.Thumbnail, ownerID, now())
	return err
}

func (s *SQLite) RemovePlaylistTrack(ctx context.Context, playlistID, ownerID, videoID string) error {
	if err := s.assertOwner(ctx, playlistID, ownerID); err != nil {
		return err
	}
	_, err := s.db.ExecContext(ctx,
		`DELETE FROM playlist_tracks WHERE playlist_id = ? AND video_id = ?`, playlistID, videoID)
	return err
}

func (s *SQLite) ReorderPlaylistTracks(ctx context.Context, playlistID, ownerID string, videoIDsInOrder []string) error {
	if err := s.assertOwner(ctx, playlistID, ownerID); err != nil {
		return err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for i, vid := range videoIDsInOrder {
		if _, err := tx.ExecContext(ctx,
			`UPDATE playlist_tracks SET position = ? WHERE playlist_id = ? AND video_id = ?`,
			i, playlistID, vid); err != nil {
			return err
		}
	}
	if _, err := tx.ExecContext(ctx, `UPDATE playlists SET updated_at = ? WHERE id = ?`, now(), playlistID); err != nil {
		return err
	}
	return tx.Commit()
}

// --- library ---

func (s *SQLite) LikeTrack(ctx context.Context, userID string, t domain.LikedTrack) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO liked_tracks (user_id, video_id, title, uploader, duration, thumbnail, liked_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(user_id, video_id) DO UPDATE SET
		   title=excluded.title, uploader=excluded.uploader,
		   duration=excluded.duration, thumbnail=excluded.thumbnail`,
		userID, t.VideoID, t.Title, t.Uploader, t.Duration, t.Thumbnail, now())
	return err
}

func (s *SQLite) UnlikeTrack(ctx context.Context, userID, videoID string) error {
	_, err := s.db.ExecContext(ctx,
		`DELETE FROM liked_tracks WHERE user_id = ? AND video_id = ?`, userID, videoID)
	return err
}

func (s *SQLite) ListLikedTracks(ctx context.Context, userID string) ([]domain.LikedTrack, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT video_id, title, uploader, duration, thumbnail, liked_at
		 FROM liked_tracks WHERE user_id = ? ORDER BY liked_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.LikedTrack{}
	for rows.Next() {
		var t domain.LikedTrack
		var liked string
		if err := rows.Scan(&t.VideoID, &t.Title, &t.Uploader, &t.Duration, &t.Thumbnail, &liked); err != nil {
			return nil, err
		}
		t.LikedAt = parseTime(liked)
		out = append(out, t)
	}
	return out, rows.Err()
}

func (s *SQLite) SavePlaylist(ctx context.Context, userID, playlistID string) error {
	if _, err := s.ownerOf(ctx, playlistID); err != nil {
		return err // ErrNotFound if playlist missing
	}
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO saved_playlists (user_id, playlist_id, saved_at) VALUES (?, ?, ?)
		 ON CONFLICT(user_id, playlist_id) DO NOTHING`,
		userID, playlistID, now())
	return err
}

func (s *SQLite) UnsavePlaylist(ctx context.Context, userID, playlistID string) error {
	_, err := s.db.ExecContext(ctx,
		`DELETE FROM saved_playlists WHERE user_id = ? AND playlist_id = ?`, userID, playlistID)
	return err
}

func (s *SQLite) ListSavedPlaylists(ctx context.Context, userID string) ([]domain.Playlist, error) {
	return s.listPlaylists(ctx,
		`SELECT p.id, p.owner_id, p.name, p.description, p.cover_url, p.visibility,
			COALESCE(p.share_token,''), p.created_at, p.updated_at
		 FROM playlists p
		 JOIN saved_playlists sp ON sp.playlist_id = p.id
		 WHERE sp.user_id = ? ORDER BY sp.saved_at DESC`, userID)
}

// --- history ---

func (s *SQLite) RecordPlay(ctx context.Context, userID string, p domain.PlayEvent) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO listening_history
			(user_id, video_id, title, uploader, duration, thumbnail,
			 played_at, last_position, context_kind, context_id, context_title)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		userID, p.VideoID, p.Title, p.Uploader, p.Duration, p.Thumbnail,
		now(), p.Position, p.ContextKind, p.ContextID, p.ContextTitle)
	return err
}

// ListHistory groups by video_id, returning one entry per distinct video,
// ordered by most-recent play. Each entry's metadata + context is taken from
// the most-recent row for that video. SQLite doesn't support ANY_VALUE, so we
// use a subquery to pick the row directly.
func (s *SQLite) ListHistory(ctx context.Context, userID string, limit int) ([]domain.HistoryEntry, error) {
	if limit <= 0 {
		limit = 20
	}
	rows, err := s.db.QueryContext(ctx,
		`SELECT h.video_id, h.title, h.uploader, h.duration, h.thumbnail,
		        h.played_at, h.last_position,
		        (SELECT COUNT(*) FROM listening_history h2
		         WHERE h2.user_id = h.user_id AND h2.video_id = h.video_id),
		        h.context_kind, h.context_id, h.context_title
		 FROM listening_history h
		 WHERE h.user_id = ?
		   AND h.played_at = (SELECT MAX(played_at) FROM listening_history h2
		                      WHERE h2.user_id = h.user_id AND h2.video_id = h.video_id)
		 ORDER BY h.played_at DESC
		 LIMIT ?`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]domain.HistoryEntry, 0, limit)
	for rows.Next() {
		var e domain.HistoryEntry
		var lastPlayed string
		if err := rows.Scan(&e.VideoID, &e.Title, &e.Uploader, &e.Duration, &e.Thumbnail,
			&lastPlayed, &e.LastPosition, &e.PlayCount,
			&e.ContextKind, &e.ContextID, &e.ContextTitle); err != nil {
			return nil, err
		}
		e.LastPlayedAt = parseTime(lastPlayed)
		e.IsLongForm = e.Duration > domain.LongFormThreshold
		out = append(out, e)
	}
	return out, rows.Err()
}

func (s *SQLite) LatestContinueCard(ctx context.Context, userID string) (domain.ContinueCard, error) {
	var c domain.ContinueCard
	var lastPlayed string
	err := s.db.QueryRowContext(ctx,
		`SELECT h.context_kind, h.context_id, h.context_title, h.played_at,
		        (SELECT COUNT(*) FROM listening_history h2
		         WHERE h2.user_id = h.user_id AND h2.context_kind = h.context_kind AND h2.context_id = h.context_id)
		 FROM listening_history h
		 WHERE h.user_id = ? AND h.context_kind IN ('playlist','channel')
		   AND h.played_at = (SELECT MAX(played_at) FROM listening_history h2
		                      WHERE h2.user_id = h.user_id AND h2.context_kind = h.context_kind AND h2.context_id = h.context_id)
		 ORDER BY h.played_at DESC LIMIT 1`, userID).
		Scan(&c.Kind, &c.ID, &c.Title, &lastPlayed, &c.PlayCount)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.ContinueCard{}, ErrNotFound
	}
	if err != nil {
		return domain.ContinueCard{}, err
	}
	c.LastPlayedAt = parseTime(lastPlayed)
	return c, nil
}

func (s *SQLite) DeleteHistoryTrack(ctx context.Context, userID, videoID string) error {
	_, err := s.db.ExecContext(ctx,
		`DELETE FROM listening_history WHERE user_id = ? AND video_id = ?`,
		userID, videoID)
	return err
}

func (s *SQLite) ClearHistory(ctx context.Context, userID string) error {
	_, err := s.db.ExecContext(ctx,
		`DELETE FROM listening_history WHERE user_id = ?`, userID)
	return err
}
