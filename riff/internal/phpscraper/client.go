package phpscraper

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"riff/m/internal/ytdl"
)

const userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

// cookieTTL is shorter than the challenge's own max-age=21600 (6h) so we
// refresh before the host would reject a stale cookie.
const cookieTTL = 5 * time.Hour

// Client implements ytdl.Source by calling PHP scraper scripts hosted on
// InfinityFree. It does not implement ResolveStream: format/signature
// extraction stays on the real yt-dlp client (see ytdl.Source).
type Client struct {
	baseURL string
	http    *http.Client

	mu        sync.Mutex
	cookie    string
	cookieSet time.Time
}

var _ ytdl.Source = (*Client)(nil)

func New(baseURL string) *Client {
	return &Client{
		baseURL: baseURL,
		http:    &http.Client{Timeout: 20 * time.Second},
	}
}

// get performs a GET against baseURL+path, transparently solving the anti-bot
// challenge (once, cached for cookieTTL) if the host presents one.
func (c *Client) get(ctx context.Context, path string, query url.Values) ([]byte, error) {
	full := c.baseURL + path
	if q := query.Encode(); q != "" {
		full += "?" + q
	}
	return c.roundtrip(ctx, func() (*http.Request, error) {
		return http.NewRequestWithContext(ctx, http.MethodGet, full, nil)
	})
}

// postForm performs a form-encoded POST against baseURL+path, with the same
// challenge-solving behavior as get. extraHeaders is applied to every attempt
// (e.g. the updater's auth token).
func (c *Client) postForm(ctx context.Context, path string, form url.Values, extraHeaders map[string]string) ([]byte, error) {
	full := c.baseURL + path
	body := form.Encode()
	return c.roundtrip(ctx, func() (*http.Request, error) {
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, full, strings.NewReader(body))
		if err != nil {
			return nil, err
		}
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		for k, v := range extraHeaders {
			req.Header.Set(k, v)
		}
		return req, nil
	})
}

// roundtrip sends the request built by buildReq, solving and retrying once on
// the anti-bot challenge. buildReq is called again for the retry since
// http.Request bodies can't be reused after being read.
func (c *Client) roundtrip(ctx context.Context, buildReq func() (*http.Request, error)) ([]byte, error) {
	body, err := c.send(buildReq)
	if err != nil {
		return nil, err
	}
	if !isChallenge(string(body)) {
		return body, nil
	}

	cookie, err := solveChallenge(string(body))
	if err != nil {
		return nil, fmt.Errorf("phpscraper: %w", err)
	}
	c.mu.Lock()
	c.cookie = cookie
	c.cookieSet = time.Now()
	c.mu.Unlock()

	body, err = c.send(buildReq)
	if err != nil {
		return nil, err
	}
	if isChallenge(string(body)) {
		return nil, fmt.Errorf("phpscraper: still challenged after solving cookie")
	}
	return body, nil
}

func (c *Client) send(buildReq func() (*http.Request, error)) ([]byte, error) {
	req, err := buildReq()
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", userAgent)

	c.mu.Lock()
	cookie := c.cookie
	fresh := cookie != "" && time.Since(c.cookieSet) < cookieTTL
	c.mu.Unlock()
	if fresh {
		req.AddCookie(&http.Cookie{Name: challengeCookieName, Value: cookie})
	}

	res, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	data, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, err
	}
	if res.StatusCode != http.StatusOK && res.StatusCode != http.StatusForbidden && res.StatusCode != http.StatusBadRequest {
		return nil, fmt.Errorf("phpscraper: %s -> %d", req.URL, res.StatusCode)
	}
	return data, nil
}

// jsonEntry mirrors the JSON shape emitted by search.php/video.php/
// playlist.php/channel.php for one video.
type jsonEntry struct {
	ID          string  `json:"id"`
	Title       string  `json:"title"`
	Uploader    string  `json:"uploader"`
	Channel     string  `json:"channel"`
	ChannelID   string  `json:"channelId"`
	Duration    float64 `json:"duration"`
	Thumbnail   string  `json:"thumbnail"`
	UploadDate  string  `json:"uploadDate"`
	ViewCount   int64   `json:"viewCount"`
	Description string  `json:"description"`
}

func (e jsonEntry) toInfo() ytdl.Info {
	return ytdl.Info{
		ID:          e.ID,
		Title:       e.Title,
		Uploader:    e.Uploader,
		Channel:     e.Channel,
		ChannelID:   e.ChannelID,
		Duration:    e.Duration,
		Thumbnail:   firstNonEmpty(e.Thumbnail, ytdl.CanonicalThumbnail(e.ID)),
		UploadDate:  e.UploadDate,
		ViewCount:   e.ViewCount,
		Description: e.Description,
	}
}

func (c *Client) Search(ctx context.Context, query string, limit int) ([]ytdl.Info, error) {
	if limit <= 0 {
		limit = 20
	}
	body, err := c.get(ctx, "/search.php", url.Values{
		"q":     {query},
		"limit": {fmt.Sprint(limit)},
	})
	if err != nil {
		return nil, err
	}
	var entries []jsonEntry
	if err := json.Unmarshal(body, &entries); err != nil {
		return nil, fmt.Errorf("phpscraper: search.php decode: %w", err)
	}
	out := make([]ytdl.Info, 0, len(entries))
	for _, e := range entries {
		if e.ID == "" {
			continue
		}
		out = append(out, e.toInfo())
	}
	return out, nil
}

func (c *Client) ResolveInfo(ctx context.Context, videoID string) (ytdl.Info, error) {
	body, err := c.get(ctx, "/video.php", url.Values{"id": {videoID}})
	if err != nil {
		return ytdl.Info{}, err
	}
	var e jsonEntry
	if err := json.Unmarshal(body, &e); err != nil {
		return ytdl.Info{}, fmt.Errorf("phpscraper: video.php decode: %w", err)
	}
	if e.ID == "" {
		return ytdl.Info{}, fmt.Errorf("phpscraper: video %s not found", videoID)
	}
	return e.toInfo(), nil
}

type jsonList struct {
	Title   string      `json:"title"`
	Entries []jsonEntry `json:"entries"`
}

func (c *Client) Playlist(ctx context.Context, playlistID string) (string, []ytdl.Info, error) {
	body, err := c.get(ctx, "/playlist.php", url.Values{"id": {playlistID}})
	if err != nil {
		return "", nil, err
	}
	var list jsonList
	if err := json.Unmarshal(body, &list); err != nil {
		return "", nil, fmt.Errorf("phpscraper: playlist.php decode: %w", err)
	}
	return list.Title, toInfos(list.Entries), nil
}

func (c *Client) Channel(ctx context.Context, channelID string) (string, []ytdl.Info, error) {
	body, err := c.get(ctx, "/channel.php", url.Values{"id": {channelID}})
	if err != nil {
		return "", nil, err
	}
	var list jsonList
	if err := json.Unmarshal(body, &list); err != nil {
		return "", nil, fmt.Errorf("phpscraper: channel.php decode: %w", err)
	}
	return list.Title, toInfos(list.Entries), nil
}

func (c *Client) Thumbnail(videoID string) string { return ytdl.CanonicalThumbnail(videoID) }

func toInfos(entries []jsonEntry) []ytdl.Info {
	out := make([]ytdl.Info, 0, len(entries))
	for _, e := range entries {
		if e.ID == "" {
			continue
		}
		out = append(out, e.toInfo())
	}
	return out
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}
