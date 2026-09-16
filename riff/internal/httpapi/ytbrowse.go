package httpapi

import (
	"net/http"

	"riff/m/internal/domain"
)

func (s *Server) handleYTPlaylist(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	title, hits, err := s.meta.Playlist(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusBadGateway, "playlist failed: "+err.Error())
		return
	}
	entries := make([]domain.SearchResult, 0, len(hits))
	for _, h := range hits {
		uploader := h.Uploader
		entries = append(entries, domain.SearchResult{
			ID:        h.ID,
			Title:     h.Title,
			Uploader:  uploader,
			Duration:  h.Duration,
			Thumbnail: h.Thumbnail,
			Type:      "video",
		})
	}
	s.writeCachedJSON(w, "ytpl|"+id, s.cfg.CacheMetadataTTL, domain.ExternalPlaylist{
		ID:      id,
		Title:   title,
		Entries: entries,
	})
}

func (s *Server) handleYTChannel(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	title, hits, err := s.meta.Channel(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusBadGateway, "channel failed: "+err.Error())
		return
	}
	entries := make([]domain.SearchResult, 0, len(hits))
	for _, h := range hits {
		entries = append(entries, domain.SearchResult{
			ID:        h.ID,
			Title:     h.Title,
			Uploader:  h.Uploader,
			Duration:  h.Duration,
			Thumbnail: h.Thumbnail,
			Type:      "video",
		})
	}
	s.writeCachedJSON(w, "ytch|"+id, s.cfg.CacheMetadataTTL, domain.ExternalChannel{
		ID:      id,
		Title:   title,
		Entries: entries,
	})
}
