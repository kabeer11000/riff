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
	typ := r.URL.Query().Get("type")

	results, err := s.ytdl.Search(r.Context(), q, limit, typ)
	if err != nil {
		writeError(w, http.StatusBadGateway, "search failed: "+err.Error())
		return
	}
	s.writeCachedJSON(w,
		fmt.Sprintf("search|%s|%d|%s", q, limit, typ),
		s.cfg.CacheSearchTTL,
		map[string]any{"results": results},
	)
}