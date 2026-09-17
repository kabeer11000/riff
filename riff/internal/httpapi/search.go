package httpapi

import (
	"fmt"
	"net/http"
	"strconv"
)

func (s *Server) handleSearch(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query().Get("q")
	if q == "" {
		writeError(w, http.StatusBadRequest, "missing q")
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	_ = r.URL.Query().Get("type") // accepted for back-compat; Registry returns items of any type

	cacheKey := fmt.Sprintf("search|%s|%d", q, limit)
	if e, ok := s.jsonCache.Get(cacheKey); ok {
		writeCachedBody(w, e)
		return
	}

	results, err := s.providers.SearchAll(r.Context(), q, limit)
	if err != nil {
		writeError(w, http.StatusBadGateway, "search failed: "+err.Error())
		return
	}
	items, err := s.indexer.Index(r.Context(), "youtube", results)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	hits := make([]map[string]any, 0, len(items))
	for _, it := range items {
		uploader := ""
		if len(it.Artists) > 0 {
			uploader = it.Artists[0]
		}
		typ := "video"
		if it.Duration < 600 {
			typ = "audio"
		}
		hits = append(hits, map[string]any{
			"id":        it.ID,
			"title":     it.Title,
			"uploader":  uploader,
			"duration":  it.Duration,
			"thumbnail": it.Thumbnail,
			"type":      typ,
		})
	}
	s.writeCachedJSON(w, cacheKey, s.cfg.CacheSearchTTL, map[string]any{"results": hits})
}
