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

// Repository is the persistence boundary for internal Riff data. The SQLite
// implementation lives in sqlite.go; swapping to Postgres later means a new
// implementation of this interface, not changes to handlers.
type Repository interface {
	// Users / profiles.
	EnsureUser(ctx context.Context, id string) error
	GetProfile(ctx context.Context, id string) (domain.Profile, error)
	UpdateProfile(ctx context.Context, id, displayName, avatarURL string) (domain.Profile, error)

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
	RemovePlaylistTrack(ctx context.Context, playlistID, ownerID, videoID string) error
	ReorderPlaylistTracks(ctx context.Context, playlistID, ownerID string, videoIDsInOrder []string) error

	// Library.
	LikeTrack(ctx context.Context, userID string, t domain.LikedTrack) error
	UnlikeTrack(ctx context.Context, userID, videoID string) error
	ListLikedTracks(ctx context.Context, userID string) ([]domain.LikedTrack, error)
	SavePlaylist(ctx context.Context, userID, playlistID string) error
	UnsavePlaylist(ctx context.Context, userID, playlistID string) error
	ListSavedPlaylists(ctx context.Context, userID string) ([]domain.Playlist, error)

	// History.
	RecordPlay(ctx context.Context, userID string, p domain.PlayEvent) error
	ListHistory(ctx context.Context, userID string, limit int) ([]domain.HistoryEntry, error)
	LatestContinueCard(ctx context.Context, userID string) (domain.ContinueCard, error)
	DeleteHistoryTrack(ctx context.Context, userID, videoID string) error
	ClearHistory(ctx context.Context, userID string) error

	Close() error
}
