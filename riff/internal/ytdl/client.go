package ytdl

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/wader/goutubedl"

	"riff/m/internal/domain"
)

// Client wraps goutubedl (which shells out to yt-dlp/youtube-dl).
type Client struct{}

// New configures the yt-dlp binary path (empty = look up on PATH) and returns a Client.
func New(binPath string) *Client {
	if binPath != "" {
		goutubedl.Path = binPath
	}
	return &Client{}
}

const watchURLFmt = "https://www.youtube.com/watch?v=%s"

// Search returns flat results for a YouTube search query. yt-dlp's search is
// video-oriented (ytsearch); the typ parameter is accepted for forward
// compatibility but currently only video results are returned.
func (c *Client) Search(ctx context.Context, query string, limit int, typ string) ([]domain.SearchResult, error) {
	_ = typ
	if limit <= 0 {
		limit = 20
	}
	raw := fmt.Sprintf("ytsearch%d:%s", limit, query)
	res, err := goutubedl.New(ctx, raw, goutubedl.Options{
		Type:         goutubedl.TypePlaylist,
		FlatPlaylist: true,
	})
	if err != nil {
		return nil, err
	}
	return entriesToResults(res.Info.Entries), nil
}

// Resolve returns metadata + playable formats for a single video.
func (c *Client) Resolve(ctx context.Context, videoID string) (domain.TrackInfo, error) {
	res, err := goutubedl.New(ctx, fmt.Sprintf(watchURLFmt, videoID), goutubedl.Options{
		Type: goutubedl.TypeSingle,
	})
	if err != nil {
		return domain.TrackInfo{}, err
	}
	formats, err := parseFormats(res.RawJSON)
	if err != nil {
		return domain.TrackInfo{}, err
	}
	info := res.Info
	ti := domain.TrackInfo{
		ID:          info.ID,
		Title:       info.Title,
		Uploader:    firstNonEmpty(info.Uploader, info.Channel),
		ChannelID:   info.ChannelID,
		Duration:    info.Duration,
		Thumbnail:   info.Thumbnail,
		Description: info.Description,
		Artist:      info.Artist,
		Album:       info.Album,
		UploadDate:  info.UploadDate,
		ViewCount:   info.ViewCount,
	}
	for _, f := range formats {
		if f.Kind == "" {
			continue
		}
		ti.Formats = append(ti.Formats, domain.FormatInfo{
			FormatID: f.FormatID,
			Ext:      f.Ext,
			Kind:     f.Kind,
			ACodec:   f.ACodec,
			VCodec:   f.VCodec,
			ABR:      f.ABR,
			Height:   f.Height,
			Filesize: f.Filesize,
		})
	}
	return ti, nil
}

// ResolvedStream is a single directly-fetchable format URL.
type ResolvedStream struct {
	URL         string
	ContentType string
	Kind        string
	ExpiresAt   time.Time // from the googlevideo `expire` param; zero if unknown
}

// ResolveStream resolves a video and picks the best directly-proxyable format of
// the requested kind ("audio" or "muxed").
func (c *Client) ResolveStream(ctx context.Context, videoID, kind string) (ResolvedStream, error) {
	res, err := goutubedl.New(ctx, fmt.Sprintf(watchURLFmt, videoID), goutubedl.Options{
		Type: goutubedl.TypeSingle,
	})
	if err != nil {
		return ResolvedStream{}, err
	}
	formats, err := parseFormats(res.RawJSON)
	if err != nil {
		return ResolvedStream{}, err
	}
	best := pickBest(formats, kind)
	if best == nil {
		return ResolvedStream{}, fmt.Errorf("no directly-proxyable %s format for %s", kind, videoID)
	}
	rs := ResolvedStream{URL: best.URL, ContentType: contentType(best), Kind: kind}
	if exp := parseExpire(best.URL); exp > 0 {
		rs.ExpiresAt = time.Unix(exp, 0)
	}
	return rs, nil
}

// Playlist resolves an external YouTube playlist (flat).
func (c *Client) Playlist(ctx context.Context, playlistID string) (domain.ExternalPlaylist, error) {
	res, err := goutubedl.New(ctx, "https://www.youtube.com/playlist?list="+playlistID, goutubedl.Options{
		Type:         goutubedl.TypePlaylist,
		FlatPlaylist: true,
	})
	if err != nil {
		return domain.ExternalPlaylist{}, err
	}
	return domain.ExternalPlaylist{
		ID:      firstNonEmpty(res.Info.ID, playlistID),
		Title:   res.Info.Title,
		Entries: entriesToResults(res.Info.Entries),
	}, nil
}

// Channel resolves an external YouTube channel (flat).
func (c *Client) Channel(ctx context.Context, channelID string) (domain.ExternalChannel, error) {
	res, err := goutubedl.New(ctx, "https://www.youtube.com/channel/"+channelID, goutubedl.Options{
		Type:         goutubedl.TypeChannel,
		FlatPlaylist: true,
	})
	if err != nil {
		return domain.ExternalChannel{}, err
	}
	return domain.ExternalChannel{
		ID:      firstNonEmpty(res.Info.ID, channelID),
		Title:   res.Info.Title,
		Entries: entriesToResults(res.Info.Entries),
	}, nil
}

func entriesToResults(entries []goutubedl.Info) []domain.SearchResult {
	out := make([]domain.SearchResult, 0, len(entries))
	for _, e := range entries {
		if e.ID == "" {
			continue
		}
		out = append(out, domain.SearchResult{
			ID:        e.ID,
			Title:     e.Title,
			Uploader:  firstNonEmpty(e.Uploader, e.Channel),
			Duration:  e.Duration,
			Thumbnail: firstNonEmpty(e.Thumbnail, ytThumbnail(e.ID)),
			Type:      entryType(e.Type),
		})
	}
	return out
}

// ytThumbnail returns a deterministic YouTube thumbnail URL for a video ID.
// Used as a fallback when yt-dlp's flat listing does not include thumbnails,
// so search/playlist/channel listings don't all show empty strings.
func ytThumbnail(videoID string) string {
	return "https://i.ytimg.com/vi/" + videoID + "/hqdefault.jpg"
}

// Thumbnail returns the canonical YouTube thumbnail URL for a video ID.
func (c *Client) Thumbnail(videoID string) string { return ytThumbnail(videoID) }

func entryType(t string) string {
	switch t {
	case "playlist", "multi_video":
		return "playlist"
	case "channel":
		return "channel"
	default:
		return "video"
	}
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}

// parseExpire extracts the unix `expire` query param from a googlevideo URL.
// Returns 0 if absent/unparseable.
func parseExpire(rawURL string) int64 {
	// Cheap scan avoids a full url.Parse on every stream request.
	const marker = "expire="
	i := indexOf(rawURL, marker)
	if i < 0 {
		return 0
	}
	start := i + len(marker)
	end := start
	for end < len(rawURL) && rawURL[end] >= '0' && rawURL[end] <= '9' {
		end++
	}
	if end == start {
		return 0
	}
	v, err := strconv.ParseInt(rawURL[start:end], 10, 64)
	if err != nil {
		return 0
	}
	return v
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
