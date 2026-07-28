package ytdl

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/wader/goutubedl"

	"riff/m/internal/proxy"
)

// Client wraps goutubedl (which shells out to yt-dlp/youtube-dl). It exposes
// only the two operations the rest of riff needs from yt-dlp:
//   1. Search: flat listing of hits.
//   2. Stream resolution: best directly-proxyable format URL for a video id.
// Higher-level metadata (artist, album, thumbnail) is read from the raw Info
// struct by the provider layer.
type Client struct {
	cookiesFile string      // empty = no cookies
	pool        *proxy.Pool // nil = no proxy rotation
}

func New(binPath, cookiesFile string, pool *proxy.Pool) *Client {
	if binPath != "" {
		goutubedl.Path = binPath
	}
	return &Client{cookiesFile: cookiesFile, pool: pool}
}

// ytOptions returns the goutubedl options configured for this client. Callers
// pass it to goutubedl.New; passing an empty Cookies means yt-dlp runs without
// authentication, which is fine for some sites but YouTube will block it.
func (c *Client) ytOptions(modify ...func(*goutubedl.Options)) goutubedl.Options {
	o := goutubedl.Options{Cookies: c.cookiesFile}
	if c.pool != nil {
		o.ProxyUrl = c.pool.Next()
	}
	for _, m := range modify {
		m(&o)
	}
	return o
}

// Pool exposes the proxy pool so callers can MarkFailed() on network errors.
func (c *Client) Pool() *proxy.Pool { return c.pool }

const watchURLFmt = "https://www.youtube.com/watch?v=%s"

// Info is the subset of yt-dlp metadata riff cares about. Returned by Search
// and ResolveInfo; higher layers map this into provider.Result.
type Info struct {
	ID          string
	Title       string
	Uploader    string
	Channel     string
	ChannelID   string
	Duration    float64
	Thumbnail   string
	Artist      string
	Album       string
	UploadDate  string
	ViewCount   int64
	Description string
}

// Search returns flat results for a YouTube search query.
func (c *Client) Search(ctx context.Context, query string, limit int) ([]Info, error) {
	if limit <= 0 {
		limit = 20
	}
	raw := fmt.Sprintf("ytsearch%d:%s", limit, query)
	res, err := goutubedl.New(ctx, raw, c.ytOptions(func(o *goutubedl.Options) {
		o.Type = goutubedl.TypePlaylist
		o.FlatPlaylist = true
	}))
	if err != nil {
		return nil, err
	}
	out := make([]Info, 0, len(res.Info.Entries))
	for _, e := range res.Info.Entries {
		if e.ID == "" {
			continue
		}
		out = append(out, Info{
			ID:        e.ID,
			Title:     e.Title,
			Uploader:  e.Uploader,
			Channel:   e.Channel,
			ChannelID: e.ChannelID,
			Duration:  e.Duration,
			Thumbnail: firstNonEmpty(e.Thumbnail, ytThumbnail(e.ID)),
		})
	}
	return out, nil
}

// ResolveInfo returns metadata for a single YouTube video.
func (c *Client) ResolveInfo(ctx context.Context, videoID string) (Info, error) {
	res, err := goutubedl.New(ctx, fmt.Sprintf(watchURLFmt, videoID), c.ytOptions(func(o *goutubedl.Options) {
		o.Type = goutubedl.TypeSingle
	}))
	if err != nil {
		return Info{}, err
	}
	info := res.Info
	return Info{
		ID:          info.ID,
		Title:       info.Title,
		Uploader:    info.Uploader,
		Channel:     info.Channel,
		ChannelID:   info.ChannelID,
		Duration:    info.Duration,
		Thumbnail:   info.Thumbnail,
		Artist:      info.Artist,
		Album:       info.Album,
		UploadDate:  info.UploadDate,
		ViewCount:   int64(info.ViewCount),
		Description: info.Description,
	}, nil
}

// ResolvedStream is a single directly-fetchable format URL.
type ResolvedStream struct {
	URL         string
	ContentType string
	Kind        string
	ExpiresAt   time.Time
}

// ResolveStream resolves a video and picks the best directly-proxyable
// format of the requested kind ("audio" or "muxed").
func (c *Client) ResolveStream(ctx context.Context, videoID, kind string) (ResolvedStream, error) {
	res, err := goutubedl.New(ctx, fmt.Sprintf(watchURLFmt, videoID), c.ytOptions(func(o *goutubedl.Options) {
		o.Type = goutubedl.TypeSingle
	}))
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

// Playlist returns the flat listing of an external YouTube playlist.
func (c *Client) Playlist(ctx context.Context, playlistID string) (string, []Info, error) {
	res, err := goutubedl.New(ctx, "https://www.youtube.com/playlist?list="+playlistID, c.ytOptions(func(o *goutubedl.Options) {
		o.Type = goutubedl.TypePlaylist
		o.FlatPlaylist = true
	}))
	if err != nil {
		return "", nil, err
	}
	title := firstNonEmpty(res.Info.ID, playlistID)
	if res.Info.Title != "" {
		title = res.Info.Title
	}
	out := make([]Info, 0, len(res.Info.Entries))
	for _, e := range res.Info.Entries {
		if e.ID == "" {
			continue
		}
		out = append(out, Info{
			ID:        e.ID,
			Title:     e.Title,
			Uploader:  firstNonEmpty(e.Uploader, e.Channel),
			Duration:  e.Duration,
			Thumbnail: firstNonEmpty(e.Thumbnail, ytThumbnail(e.ID)),
		})
	}
	return title, out, nil
}

// Channel returns the flat listing of an external YouTube channel.
func (c *Client) Channel(ctx context.Context, channelID string) (string, []Info, error) {
	res, err := goutubedl.New(ctx, "https://www.youtube.com/channel/"+channelID, c.ytOptions(func(o *goutubedl.Options) {
		o.Type = goutubedl.TypeChannel
		o.FlatPlaylist = true
	}))
	if err != nil {
		return "", nil, err
	}
	out := make([]Info, 0, len(res.Info.Entries))
	for _, e := range res.Info.Entries {
		if e.ID == "" {
			continue
		}
		out = append(out, Info{
			ID:        e.ID,
			Title:     e.Title,
			Uploader:  firstNonEmpty(e.Uploader, e.Channel),
			Duration:  e.Duration,
			Thumbnail: firstNonEmpty(e.Thumbnail, ytThumbnail(e.ID)),
		})
	}
	return res.Info.Title, out, nil
}

// Thumbnail returns the canonical YouTube thumbnail URL for a video id.
func (c *Client) Thumbnail(videoID string) string { return ytThumbnail(videoID) }

func ytThumbnail(videoID string) string {
	return "https://i.ytimg.com/vi/" + videoID + "/hqdefault.jpg"
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
func parseExpire(rawURL string) int64 {
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
