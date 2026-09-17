package httpapi

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"riff/m/internal/cache"
	"riff/m/internal/domain"
	"riff/m/internal/provider"
	"riff/m/internal/stream"
)

func (s *Server) handleGetItem(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	it, err := s.repo.GetItem(r.Context(), id)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, it)
}

// handleStreamItem resolves the item's first source to a googlevideo URL and
// proxies the bytes through this server. Direct client redirects don't work:
// googlevideo URLs are IP-locked to whoever resolved them (confirmed via
// direct test — fetching a Render-resolved URL from a different IP returns
// 403), so the fetch has to happen from the same IP that did the resolving.
// Only YouTube is streamable today; items without a youtube source return
// 501.
func (s *Server) handleStreamItem(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	kind := r.URL.Query().Get("kind")
	if kind == "" {
		kind = "audio"
	}
	if kind != "audio" && kind != "muxed" {
		writeError(w, http.StatusBadRequest, "kind must be audio or muxed")
		return
	}

	it, err := s.repo.GetItem(r.Context(), id)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	var externalID string
	for _, src := range it.Sources {
		if src.Provider == "youtube" {
			externalID = src.ExternalID
			break
		}
	}
	if externalID == "" {
		writeError(w, http.StatusNotImplemented, "no streamable source for this item")
		return
	}

	if e, ok := s.cache.Get(externalID, kind); ok {
		stream.Proxy(r.Context(), w, r, e.URL, e.ContentType)
		return
	}
	rs, err := s.stream.ResolveStream(r.Context(), externalID, kind)
	if err != nil {
		writeError(w, http.StatusBadGateway, "resolve failed: "+err.Error())
		return
	}
	expiresAt := time.Now().Add(s.cfg.CacheMaxTTL)
	if !rs.ExpiresAt.IsZero() && rs.ExpiresAt.Before(expiresAt) {
		expiresAt = rs.ExpiresAt
	}
	s.cache.Set(externalID, kind, cache.Entry{URL: rs.URL, ContentType: rs.ContentType, ExpiresAt: expiresAt})
	// Background enrichment: fetch the full Info (description, viewCount,
	// uploadDate) and persist it back into the source's metadata. Audio
	// doesn't wait on this — the user already has playback. Next /items/{id}
	// read returns the richer data.
	go s.enrichSourceMetadata(context.Background(), id, externalID)
	stream.Proxy(r.Context(), w, r, rs.URL, rs.ContentType)
}

func (s *Server) enrichSourceMetadata(ctx context.Context, itemID, externalID string) {
	info, err := s.meta.ResolveInfo(ctx, externalID)
	if err != nil {
		return
	}
	meta := map[string]any{}
	if info.Description != "" {
		meta["description"] = info.Description
	}
	if info.ViewCount > 0 {
		meta["viewCount"] = info.ViewCount
	}
	if info.UploadDate != "" {
		meta["uploadDate"] = info.UploadDate
	}
	if info.Channel != "" {
		meta["channelName"] = info.Channel
	}
	if info.ChannelID != "" {
		meta["channelId"] = info.ChannelID
	}
	if len(meta) == 0 {
		return
	}
	_ = s.repo.AddSource(ctx, itemID, domain.Source{
		Provider:   "youtube",
		ExternalID: externalID,
		URL:        fmt.Sprintf("https://www.youtube.com/watch?v=%s", externalID),
		Metadata:   meta,
	})
}

// handleResolveURL takes any recognised provider URL, fetches its metadata,
// indexes it (or finds an existing item by source), and returns the canonical
// Item. Lets users paste a YouTube link into search.
func (s *Server) handleResolveURL(w http.ResponseWriter, r *http.Request) {
	raw := r.URL.Query().Get("url")
	if raw == "" {
		writeError(w, http.StatusBadRequest, "missing url")
		return
	}
	providerName, externalID, ok := provider.DetectURL(raw)
	if !ok {
		writeError(w, http.StatusBadRequest, "unrecognised_url")
		return
	}
	p := s.providers.Get(providerName)
	if p == nil {
		writeError(w, http.StatusBadGateway, "provider unavailable")
		return
	}
	result, err := p.Resolve(r.Context(), externalID)
	if err != nil {
		writeError(w, http.StatusBadGateway, "resolve failed: "+err.Error())
		return
	}
	items, err := s.indexer.Index(r.Context(), providerName, []provider.Result{result})
	if err != nil {
		writeStoreError(w, err)
		return
	}
	if len(items) == 0 {
		writeError(w, http.StatusInternalServerError, "internal")
		return
	}
	writeJSON(w, http.StatusOK, items[0])
}
