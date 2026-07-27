package httpapi

import "net/http"

func (s *Server) handleYTPlaylist(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	pl, err := s.ytdl.Playlist(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusBadGateway, "playlist failed: "+err.Error())
		return
	}
	s.writeCachedJSON(w, "ytpl|"+id, s.cfg.CacheMetadataTTL, pl)
}

func (s *Server) handleYTChannel(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	ch, err := s.ytdl.Channel(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusBadGateway, "channel failed: "+err.Error())
		return
	}
	s.writeCachedJSON(w, "ytch|"+id, s.cfg.CacheMetadataTTL, ch)
}