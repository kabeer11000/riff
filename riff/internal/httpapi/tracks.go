package httpapi

import (
	"net/http"
	"time"

	"riff/m/internal/cache"
	"riff/m/internal/stream"
)

func (s *Server) handleGetTrack(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	ti, err := s.ytdl.Resolve(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusBadGateway, "resolve failed: "+err.Error())
		return
	}
	s.writeCachedJSON(w, "track|"+id, s.cfg.CacheMetadataTTL, ti)
}

func (s *Server) handleStream(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	kind := r.URL.Query().Get("kind")
	if kind == "" {
		kind = "audio"
	}
	if kind != "audio" && kind != "muxed" {
		writeError(w, http.StatusBadRequest, "kind must be audio or muxed")
		return
	}

	if e, ok := s.cache.Get(id, kind); ok {
		stream.Proxy(r.Context(), w, r, e.URL, e.ContentType)
		return
	}

	rs, err := s.ytdl.ResolveStream(r.Context(), id, kind)
	if err != nil {
		writeError(w, http.StatusBadGateway, "resolve failed: "+err.Error())
		return
	}

	expiresAt := time.Now().Add(s.cfg.CacheMaxTTL)
	if !rs.ExpiresAt.IsZero() && rs.ExpiresAt.Before(expiresAt) {
		expiresAt = rs.ExpiresAt
	}
	s.cache.Set(id, kind, cache.Entry{URL: rs.URL, ContentType: rs.ContentType, ExpiresAt: expiresAt})

	stream.Proxy(r.Context(), w, r, rs.URL, rs.ContentType)
}
