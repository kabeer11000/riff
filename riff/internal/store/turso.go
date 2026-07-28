package store

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/base32"
	"encoding/json"
	"errors"
	"time"

	_ "github.com/tursodatabase/libsql-client-go/libsql"

	"riff/m/internal/domain"
)

// Turso is the libsql-client-go-backed Repository implementation.
// Connects to a remote Turso instance via libsql:// + auth token.
type Turso struct {
	db *sql.DB
}

// OpenTurso dials libsql://url with ?authToken=token, applies the schema, and
// returns a Repository. The pool is sized for a remote HTTP transport: a small
// fan-out for read parallelism, a short idle timeout so Render's NAT
// idle-kills don't leave a stale connection behind, and a lifetime cap to
// recycle long-running connections.
func OpenTurso(dbURL, authToken string) (*Turso, error) {
	dsn := dbURL
	if authToken != "" {
		dsn += "?authToken=" + authToken
	}
	db, err := sql.Open("libsql", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(4)
	db.SetMaxIdleConns(4)
	db.SetConnMaxIdleTime(2 * time.Minute)
	db.SetConnMaxLifetime(30 * time.Minute)
	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, err
	}
	return &Turso{db: db}, nil
}

func (s *Turso) Close() error { return s.db.Close() }

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

func encodeArtists(artists []string) string {
	if len(artists) == 0 {
		return ""
	}
	b, _ := json.Marshal(artists)
	return string(b)
}

func decodeArtists(s string) []string {
	if s == "" {
		return nil
	}
	var out []string
	_ = json.Unmarshal([]byte(s), &out)
	return out
}

// --- users ---

func (s *Turso) EnsureUser(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO users (id, created_at) VALUES (?, ?) ON CONFLICT(id) DO NOTHING`,
		id, now())
	return err
}

func (s *Turso) GetProfile(ctx context.Context, id string) (domain.Profile, error) {
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

func (s *Turso) UpdateProfile(ctx context.Context, id, displayName, avatarURL string) (domain.Profile, error) {
	_, err := s.db.ExecContext(ctx,
		`UPDATE users SET display_name = ?, avatar_url = ? WHERE id = ?`,
		displayName, avatarURL, id)
	if err != nil {
		return domain.Profile{}, err
	}
	return s.GetProfile(ctx, id)
}

// --- items ---

func (s *Turso) GetItem(ctx context.Context, id string) (domain.Item, error) {
	var it domain.Item
	var artists, created, updated string
	err := s.db.QueryRowContext(ctx,
		`SELECT id, title, artists, album, duration, thumbnail, created_at, updated_at
		 FROM items WHERE id = ?`, id).
		Scan(&it.ID, &it.Title, &artists, &it.Album, &it.Duration, &it.Thumbnail,
			&created, &updated)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Item{}, ErrNotFound
	}
	if err != nil {
		return domain.Item{}, err
	}
	_ = created
	_ = updated
	it.Artists = decodeArtists(artists)

	srcs, err := s.sourcesForItem(ctx, id)
	if err != nil {
		return domain.Item{}, err
	}
	it.Sources = srcs
	return it, nil
}

func (s *Turso) sourcesForItem(ctx context.Context, itemID string) ([]domain.Source, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT provider, external_id, url, metadata FROM sources WHERE item_id = ? ORDER BY created_at ASC`,
		itemID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.Source{}
	for rows.Next() {
		var (
			src     domain.Source
			metaRaw string
		)
		if err := rows.Scan(&src.Provider, &src.ExternalID, &src.URL, &metaRaw); err != nil {
			return nil, err
		}
		if metaRaw != "" && metaRaw != "{}" {
			var meta map[string]any
			if err := json.Unmarshal([]byte(metaRaw), &meta); err == nil {
				src.Metadata = meta
			}
		}
		out = append(out, src)
	}
	return out, rows.Err()
}

// --- playlists ---

func (s *Turso) ownerOf(ctx context.Context, playlistID string) (string, error) {
	var owner string
	err := s.db.QueryRowContext(ctx,
		`SELECT owner_id FROM playlists WHERE id = ?`, playlistID).Scan(&owner)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrNotFound
	}
	return owner, err
}

func (s *Turso) assertOwner(ctx context.Context, playlistID, ownerID string) error {
	owner, err := s.ownerOf(ctx, playlistID)
	if err != nil {
		return err
	}
	if owner != ownerID {
		return ErrForbidden
	}
	return nil
}

func (s *Turso) CreatePlaylist(ctx context.Context, ownerID, name, description, visibility string) (domain.Playlist, error) {
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

func (s *Turso) GetPlaylist(ctx context.Context, id string) (domain.Playlist, error) {
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

func (s *Turso) GetPlaylistByShareToken(ctx context.Context, token string) (domain.Playlist, error) {
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

func (s *Turso) scanPlaylist(ctx context.Context, query, arg string) (domain.Playlist, error) {
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

func (s *Turso) playlistTracks(ctx context.Context, playlistID string) ([]domain.PlaylistTrack, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT item_id, position, title, uploader, duration, thumbnail, added_at
		 FROM playlist_tracks WHERE playlist_id = ? ORDER BY position ASC`, playlistID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	tracks := []domain.PlaylistTrack{}
	for rows.Next() {
		var t domain.PlaylistTrack
		var added string
		if err := rows.Scan(&t.ItemID, &t.Position, &t.Title, &t.Uploader, &t.Duration, &t.Thumbnail, &added); err != nil {
			return nil, err
		}
		t.AddedAt = parseTime(added)
		tracks = append(tracks, t)
	}
	return tracks, rows.Err()
}

func (s *Turso) listPlaylists(ctx context.Context, query string, args ...any) ([]domain.Playlist, error) {
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

func (s *Turso) ListPlaylistsByOwner(ctx context.Context, ownerID string, onlyPublic bool) ([]domain.Playlist, error) {
	q := `SELECT id, owner_id, name, description, cover_url, visibility,
		COALESCE(share_token,''), created_at, updated_at FROM playlists WHERE owner_id = ?`
	if onlyPublic {
		q += ` AND visibility = 'public'`
	}
	q += ` ORDER BY updated_at DESC`
	return s.listPlaylists(ctx, q, ownerID)
}

func (s *Turso) UpdatePlaylist(ctx context.Context, id, ownerID, name, description, coverURL, visibility string) (domain.Playlist, error) {
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

func (s *Turso) DeletePlaylist(ctx context.Context, id, ownerID string) error {
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

func (s *Turso) SetShareToken(ctx context.Context, id, ownerID, token string) (domain.Playlist, error) {
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

func (s *Turso) AddPlaylistTrack(ctx context.Context, playlistID, ownerID string, t domain.PlaylistTrack) error {
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
		`INSERT INTO playlist_tracks (playlist_id, item_id, position, title, uploader, duration, thumbnail, added_by, added_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(playlist_id, item_id) DO NOTHING`,
		playlistID, t.ItemID, next, t.Title, t.Uploader, t.Duration, t.Thumbnail, ownerID, now())
	return err
}

func (s *Turso) RemovePlaylistTrack(ctx context.Context, playlistID, ownerID, itemID string) error {
	if err := s.assertOwner(ctx, playlistID, ownerID); err != nil {
		return err
	}
	_, err := s.db.ExecContext(ctx,
		`DELETE FROM playlist_tracks WHERE playlist_id = ? AND item_id = ?`, playlistID, itemID)
	return err
}

func (s *Turso) ReorderPlaylistTracks(ctx context.Context, playlistID, ownerID string, itemIDsInOrder []string) error {
	if err := s.assertOwner(ctx, playlistID, ownerID); err != nil {
		return err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for i, id := range itemIDsInOrder {
		if _, err := tx.ExecContext(ctx,
			`UPDATE playlist_tracks SET position = ? WHERE playlist_id = ? AND item_id = ?`,
			i, playlistID, id); err != nil {
			return err
		}
	}
	if _, err := tx.ExecContext(ctx, `UPDATE playlists SET updated_at = ? WHERE id = ?`, now(), playlistID); err != nil {
		return err
	}
	return tx.Commit()
}

// --- library ---

func (s *Turso) LikeTrack(ctx context.Context, userID string, t domain.LikedTrack) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO liked_tracks (user_id, item_id, title, uploader, duration, thumbnail, liked_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(user_id, item_id) DO UPDATE SET
		   title=excluded.title, uploader=excluded.uploader,
		   duration=excluded.duration, thumbnail=excluded.thumbnail`,
		userID, t.ItemID, t.Title, t.Uploader, t.Duration, t.Thumbnail, now())
	return err
}

func (s *Turso) UnlikeTrack(ctx context.Context, userID, itemID string) error {
	_, err := s.db.ExecContext(ctx,
		`DELETE FROM liked_tracks WHERE user_id = ? AND item_id = ?`, userID, itemID)
	return err
}

func (s *Turso) ListLikedTracks(ctx context.Context, userID string) ([]domain.LikedTrack, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT item_id, title, uploader, duration, thumbnail, liked_at
		 FROM liked_tracks WHERE user_id = ? ORDER BY liked_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.LikedTrack{}
	for rows.Next() {
		var t domain.LikedTrack
		var liked string
		if err := rows.Scan(&t.ItemID, &t.Title, &t.Uploader, &t.Duration, &t.Thumbnail, &liked); err != nil {
			return nil, err
		}
		t.LikedAt = parseTime(liked)
		out = append(out, t)
	}
	return out, rows.Err()
}

func (s *Turso) SavePlaylist(ctx context.Context, userID, playlistID string) error {
	if _, err := s.ownerOf(ctx, playlistID); err != nil {
		return err
	}
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO saved_playlists (user_id, playlist_id, saved_at) VALUES (?, ?, ?)
		 ON CONFLICT(user_id, playlist_id) DO NOTHING`,
		userID, playlistID, now())
	return err
}

func (s *Turso) UnsavePlaylist(ctx context.Context, userID, playlistID string) error {
	_, err := s.db.ExecContext(ctx,
		`DELETE FROM saved_playlists WHERE user_id = ? AND playlist_id = ?`, userID, playlistID)
	return err
}

func (s *Turso) ListSavedPlaylists(ctx context.Context, userID string) ([]domain.Playlist, error) {
	return s.listPlaylists(ctx,
		`SELECT p.id, p.owner_id, p.name, p.description, p.cover_url, p.visibility,
			COALESCE(p.share_token,''), p.created_at, p.updated_at
		 FROM playlists p
		 JOIN saved_playlists sp ON sp.playlist_id = p.id
		 WHERE sp.user_id = ? ORDER BY sp.saved_at DESC`, userID)
}

// --- history ---

func (s *Turso) RecordPlay(ctx context.Context, userID string, p domain.PlayEvent) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO listening_history
			(user_id, item_id, title, uploader, duration, thumbnail,
			 played_at, last_position, context_kind, context_id, context_title)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		userID, p.ItemID, p.Title, p.Uploader, p.Duration, p.Thumbnail,
		now(), p.Position, p.ContextKind, p.ContextID, p.ContextTitle)
	return err
}

func (s *Turso) ListHistory(ctx context.Context, userID string, limit int) ([]domain.HistoryEntry, error) {
	if limit <= 0 {
		limit = 20
	}
	rows, err := s.db.QueryContext(ctx,
		`SELECT h.item_id, h.title, h.uploader, h.duration, h.thumbnail,
		        h.played_at, h.last_position,
		        (SELECT COUNT(*) FROM listening_history h2
		         WHERE h2.user_id = h.user_id AND h2.item_id = h.item_id),
		        h.context_kind, h.context_id, h.context_title
		 FROM listening_history h
		 WHERE h.user_id = ?
		   AND h.played_at = (SELECT MAX(played_at) FROM listening_history h2
		                      WHERE h2.user_id = h.user_id AND h2.item_id = h.item_id)
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
		if err := rows.Scan(&e.ItemID, &e.Title, &e.Uploader, &e.Duration, &e.Thumbnail,
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

func (s *Turso) LatestContinueCard(ctx context.Context, userID string) (domain.ContinueCard, error) {
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

func (s *Turso) DeleteHistoryTrack(ctx context.Context, userID, itemID string) error {
	_, err := s.db.ExecContext(ctx,
		`DELETE FROM listening_history WHERE user_id = ? AND item_id = ?`,
		userID, itemID)
	return err
}

func (s *Turso) ClearHistory(ctx context.Context, userID string) error {
	_, err := s.db.ExecContext(ctx,
		`DELETE FROM listening_history WHERE user_id = ?`, userID)
	return err
}

// --- indexer hooks ---

func (s *Turso) LookupBySource(ctx context.Context, provider, externalID string) (string, bool, error) {
	var itemID string
	err := s.db.QueryRowContext(ctx,
		`SELECT item_id FROM sources WHERE provider = ? AND external_id = ?`,
		provider, externalID).Scan(&itemID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return itemID, true, nil
}

func (s *Turso) LookupByCanonical(ctx context.Context, isrc, mbid string) (string, bool, error) {
	if isrc == "" && mbid == "" {
		return "", false, nil
	}
	q := `SELECT id FROM items WHERE `
	args := []any{}
	if isrc != "" {
		q += `isrc = ?`
		args = append(args, isrc)
		if mbid != "" {
			q += ` OR mbid = ?`
			args = append(args, mbid)
		}
	} else {
		q += `mbid = ?`
		args = append(args, mbid)
	}
	q += ` LIMIT 1`
	var itemID string
	err := s.db.QueryRowContext(ctx, q, args...).Scan(&itemID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return itemID, true, nil
}

func (s *Turso) CreateItem(ctx context.Context, it domain.Item) (string, error) {
	id := newID()
	ts := now()
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO items (id, title, artists, album, duration, thumbnail, isrc, mbid, metadata, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		id, it.Title, encodeArtists(it.Artists), it.Album, it.Duration, it.Thumbnail,
		"", "", "{}", ts, ts)
	if err != nil {
		return "", err
	}
	return id, nil
}

func (s *Turso) AddSource(ctx context.Context, itemID string, src domain.Source) error {
	metaJSON := "{}"
	if len(src.Metadata) > 0 {
		b, err := json.Marshal(src.Metadata)
		if err != nil {
			return err
		}
		metaJSON = string(b)
	}
	// ON CONFLICT DO UPDATE so re-indexing refreshes url + metadata. View
	// counts and descriptions change over time; a re-search should pull
	// fresh data without leaving stale rows behind.
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO sources (item_id, provider, external_id, url, metadata, created_at)
		 VALUES (?, ?, ?, ?, ?, ?)
		 ON CONFLICT(provider, external_id) DO UPDATE SET
		   url = excluded.url,
		   metadata = excluded.metadata`,
		itemID, src.Provider, src.ExternalID, src.URL, metaJSON, now())
	return err
}
