package provider

import (
	"context"
	"fmt"

	"riff/m/internal/ytdl"
)

// YouTube implements Provider by delegating to a ytdl.Source (either the real
// yt-dlp-backed client or a PHP-relay-backed one).
type YouTube struct {
	c ytdl.Source
}

func NewYouTube(c ytdl.Source) *YouTube { return &YouTube{c: c} }

func (y *YouTube) Name() string { return "youtube" }

func (y *YouTube) Search(ctx context.Context, query string, limit int) ([]Result, error) {
	hits, err := y.c.Search(ctx, query, limit)
	if err != nil {
		return nil, err
	}
	out := make([]Result, 0, len(hits))
	for _, h := range hits {
		out = append(out, fromInfo(h))
	}
	return out, nil
}

func (y *YouTube) Resolve(ctx context.Context, externalID string) (Result, error) {
	info, err := y.c.ResolveInfo(ctx, externalID)
	if err != nil {
		return Result{}, err
	}
	return fromInfo(info), nil
}

func fromInfo(h ytdl.Info) Result {
	uploader := firstNonEmpty(h.Uploader, h.Channel)
	meta := map[string]any{}
	if h.Description != "" {
		meta["description"] = h.Description
	}
	if h.ViewCount > 0 {
		meta["viewCount"] = h.ViewCount
	}
	if h.UploadDate != "" {
		meta["uploadDate"] = h.UploadDate
	}
	if h.Channel != "" {
		meta["channelName"] = h.Channel
	}
	if h.ChannelID != "" {
		meta["channelId"] = h.ChannelID
	}
	return Result{
		ExternalID: h.ID,
		Title:      h.Title,
		Artists:    []string{uploader},
		Album:      h.Album,
		Duration:   h.Duration,
		Thumbnail:  h.Thumbnail,
		URL:        fmt.Sprintf("https://www.youtube.com/watch?v=%s", h.ID),
		Metadata:   meta,
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
