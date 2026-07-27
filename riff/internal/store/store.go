package store

import (
	"context"
	"errors"

	"riff/m/internal/domain"
)

var (
	ErrNotFound  = errors.New("not found")
	ErrForbidden = errors.New("forbidden")
)

// Repository is the persistence boundary for internal Riff data. The libSQL/Turso
// implementation lives in turso.go; the SQLite-shaped test impl is in
// sqlite_test.go.
type Repository interface {
	// Users / profiles.
	EnsureUser(ctx context.Context, id string) error
	GetProfile(ctx context.Context, id string) (domain.Profile, error)
	UpdateProfile(ctx context.Context, id, displayName, avatarURL string) (domain.Profile, error)

	// Items (provider-agnostic canonical record).
	GetItem(ctx context.Context, id string) (domain.Item, error)

	// Playlists.
	CreatePlaylist(ctx context.Context, ownerID, name, description, visibility string) (domain.Playlist, error)
	GetPlaylist(ctx context.Context, id string) (domain.Playlist, error)
	GetPlaylistByShareToken(ctx context.Context, token string) (domain.Playlist, error)
	ListPlaylistsByOwner(ctx context.Context, ownerID string, onlyPublic bool) ([]domain.Playlist, error)
	UpdatePlaylist(ctx context.Context, id, ownerID, name, description, coverURL, visibility string) (domain.Playlist, error)
	DeletePlaylist(ctx context.Context, id, ownerID string) error
	SetShareToken(ctx context.Context, id, ownerID, token string) (domain.Playlist, error)

	// Playlist tracks.
	AddPlaylistTrack(ctx context.Context, playlistID, ownerID string, t domain.PlaylistTrack) error
	RemovePlaylistTrack(ctx context.Context, playlistID, ownerID, itemID string) error
	ReorderPlaylistTracks(ctx context.Context, playlistID, ownerID string, itemIDsInOrder []string) error

	// Library.
	LikeTrack(ctx context.Context, userID string, t domain.LikedTrack) error
	UnlikeTrack(ctx context.Context, userID, itemID string) error
	ListLikedTracks(ctx context.Context, userID string) ([]domain.LikedTrack, error)
	SavePlaylist(ctx context.Context, userID, playlistID string) error
	UnsavePlaylist(ctx context.Context, userID, playlistID string) error
	ListSavedPlaylists(ctx context.Context, userID string) ([]domain.Playlist, error)

	// History.
	RecordPlay(ctx context.Context, userID string, p domain.PlayEvent) error
	ListHistory(ctx context.Context, userID string, limit int) ([]domain.HistoryEntry, error)
	LatestContinueCard(ctx context.Context, userID string) (domain.ContinueCard, error)
	DeleteHistoryTrack(ctx context.Context, userID, itemID string) error
	ClearHistory(ctx context.Context, userID string) error

	// Indexer hooks (provider-aware indexing of canonical items).
	LookupBySource(ctx context.Context, provider, externalID string) (itemID string, found bool, err error)
	LookupByCanonical(ctx context.Context, isrc, mbid string) (itemID string, found bool, err error)
	CreateItem(ctx context.Context, item domain.Item) (itemID string, err error)
	AddSource(ctx context.Context, itemID string, src domain.Source) error

	Close() error
}
