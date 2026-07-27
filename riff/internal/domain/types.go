package domain

import "time"

// SearchResult is one hit from a search or a flat external playlist/channel listing.
type SearchResult struct {
	ID        string  `json:"id"`
	Title     string  `json:"title"`
	Uploader  string  `json:"uploader"`
	Duration  float64 `json:"duration"`
	Thumbnail string  `json:"thumbnail"`
	Type      string  `json:"type"` // "video" | "playlist" | "channel"
}

// FormatInfo is a client-facing description of a playable format. It deliberately
// omits the direct googlevideo URL — clients stream through the proxy instead.
type FormatInfo struct {
	FormatID string  `json:"formatId"`
	Ext      string  `json:"ext"`
	Kind     string  `json:"kind"` // "audio" | "muxed"
	ACodec   string  `json:"acodec"`
	VCodec   string  `json:"vcodec"`
	ABR      float64 `json:"abr"`
	Height   float64 `json:"height"`
	Filesize float64 `json:"filesize"`
}

// TrackInfo is resolved metadata for a single YouTube video.
type TrackInfo struct {
	ID          string       `json:"id"`
	Title       string       `json:"title"`
	Uploader    string       `json:"uploader"`
	ChannelID   string       `json:"channelId"`
	Duration    float64      `json:"duration"`
	Thumbnail   string       `json:"thumbnail"`
	Description string       `json:"description"`
	Artist      string       `json:"artist"`
	Album       string       `json:"album"`
	UploadDate  string       `json:"uploadDate"`
	ViewCount   float64      `json:"viewCount"`
	Formats     []FormatInfo `json:"formats"`
}

// ExternalPlaylist / ExternalChannel are flat listings resolved live from YouTube.
type ExternalPlaylist struct {
	ID      string         `json:"id"`
	Title   string         `json:"title"`
	Entries []SearchResult `json:"entries"`
}

type ExternalChannel struct {
	ID      string         `json:"id"`
	Title   string         `json:"title"`
	Entries []SearchResult `json:"entries"`
}

// Profile is a Riff user.
type Profile struct {
	ID          string    `json:"id"`
	DisplayName string    `json:"displayName"`
	AvatarURL   string    `json:"avatarUrl"`
	CreatedAt   time.Time `json:"createdAt"`
}

// Visibility values for internal playlists.
const (
	VisibilityPublic   = "public"
	VisibilityPrivate  = "private"
	VisibilityUnlisted = "unlisted"
)

// PlaylistTrack is a track inside an internal playlist. Minimal metadata is
// denormalized so listing a playlist does not require re-resolving via yt-dlp.
type PlaylistTrack struct {
	VideoID   string    `json:"videoId"`
	Position  int       `json:"position"`
	Title     string    `json:"title"`
	Uploader  string    `json:"uploader"`
	Duration  float64   `json:"duration"`
	Thumbnail string    `json:"thumbnail"`
	AddedAt   time.Time `json:"addedAt"`
}

// Playlist is an internal, user-owned playlist.
type Playlist struct {
	ID          string          `json:"id"`
	OwnerID     string          `json:"ownerId"`
	Name        string          `json:"name"`
	Description string          `json:"description"`
	CoverURL    string          `json:"coverUrl"`
	Visibility  string          `json:"visibility"`
	ShareToken  string          `json:"shareToken,omitempty"`
	Tracks      []PlaylistTrack `json:"tracks"`
	CreatedAt   time.Time       `json:"createdAt"`
	UpdatedAt   time.Time       `json:"updatedAt"`
}

// LikedTrack is a track in a user's "liked songs" library.
type LikedTrack struct {
	VideoID   string    `json:"videoId"`
	Title     string    `json:"title"`
	Uploader  string    `json:"uploader"`
	Duration  float64   `json:"duration"`
	Thumbnail string    `json:"thumbnail"`
	LikedAt   time.Time `json:"likedAt"`
}

// LongFormThreshold is the duration above which we surface a resume-position
// indicator. Songs are short enough that resume is noise; long-form videos
// benefit from it.
const LongFormThreshold = 600.0

// PlayEvent is a single play record inserted into listening_history. Every
// play is its own row — server-side grouping happens on read.
type PlayEvent struct {
	VideoID      string
	Title        string
	Uploader     string
	Duration     float64
	Thumbnail    string
	Position     float64
	ContextKind  string // "search" | "playlist" | "channel" | "library" | ""
	ContextID    string
	ContextTitle string
}

// HistoryEntry is one deduped history item returned by ListHistory.
type HistoryEntry struct {
	VideoID      string    `json:"videoId"`
	Title        string    `json:"title"`
	Uploader     string    `json:"uploader"`
	Duration     float64   `json:"duration"`
	Thumbnail    string    `json:"thumbnail"`
	LastPlayedAt time.Time `json:"lastPlayedAt"`
	PlayCount    int       `json:"playCount"`
	LastPosition float64   `json:"lastPosition"`
	IsLongForm   bool      `json:"isLongForm"`
	ContextKind  string    `json:"contextKind"`
	ContextID    string    `json:"contextId,omitempty"`
	ContextTitle string    `json:"contextTitle,omitempty"`
}

// ContinueCard surfaces "Continue <playlist/channel>" at the top of home.
type ContinueCard struct {
	Kind         string    `json:"kind"` // "playlist" | "channel"
	ID           string    `json:"id"`
	Title        string    `json:"title"`
	Cover        string    `json:"cover,omitempty"`
	LastPlayedAt time.Time `json:"lastPlayedAt"`
	PlayCount    int       `json:"playCount"`
}
