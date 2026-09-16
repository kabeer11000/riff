package ytdl

import "context"

// Source is the metadata/discovery surface riff needs from a YouTube backend:
// search, single-item resolve, and external playlist/channel listing. It
// deliberately excludes ResolveStream — format/signature extraction needs the
// real yt-dlp client, so callers that need a stream URL take *Client directly
// rather than going through this interface. *Client and phpscraper.Client both
// implement it, so main.go can swap which one backs search/resolve/browse.
type Source interface {
	Search(ctx context.Context, query string, limit int) ([]Info, error)
	ResolveInfo(ctx context.Context, videoID string) (Info, error)
	Playlist(ctx context.Context, playlistID string) (string, []Info, error)
	Channel(ctx context.Context, channelID string) (string, []Info, error)
	Thumbnail(videoID string) string
}

// CanonicalThumbnail returns the standard YouTube thumbnail URL for a video
// id. Shared by *Client and phpscraper.Client so both Source implementations
// agree on the same thumbnail scheme.
func CanonicalThumbnail(videoID string) string { return ytThumbnail(videoID) }
