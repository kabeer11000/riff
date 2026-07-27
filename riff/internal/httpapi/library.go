package httpapi

import (
	"net/http"

	"riff/m/internal/domain"
)

func (s *Server) handleListLikes(w http.ResponseWriter, r *http.Request) {
	tracks, err := s.repo.ListLikedTracks(r.Context(), UserID(r.Context()))
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"tracks": tracks})
}

func (s *Server) handleLike(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ItemID    string  `json:"itemId"`
		Title     string  `json:"title"`
		Uploader  string  `json:"uploader"`
		Duration  float64 `json:"duration"`
		Thumbnail string  `json:"thumbnail"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if body.ItemID == "" {
		writeError(w, http.StatusBadRequest, "itemId is required")
		return
	}
	it, err := s.repo.GetItem(r.Context(), body.ItemID)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	if body.Title == "" {
		body.Title = it.Title
		body.Uploader = firstNonEmpty(body.Uploader, joinArtists(it.Artists))
		body.Duration = it.Duration
	}
	if body.Thumbnail == "" {
		body.Thumbnail = it.Thumbnail
	}
	err = s.repo.LikeTrack(r.Context(), UserID(r.Context()), domain.LikedTrack{
		ItemID:    body.ItemID,
		Title:     body.Title,
		Uploader:  body.Uploader,
		Duration:  body.Duration,
		Thumbnail: body.Thumbnail,
	})
	if err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleUnlike(w http.ResponseWriter, r *http.Request) {
	if err := s.repo.UnlikeTrack(r.Context(), UserID(r.Context()), r.PathValue("itemId")); err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleSavePlaylist(w http.ResponseWriter, r *http.Request) {
	if err := s.repo.SavePlaylist(r.Context(), UserID(r.Context()), r.PathValue("id")); err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleUnsavePlaylist(w http.ResponseWriter, r *http.Request) {
	if err := s.repo.UnsavePlaylist(r.Context(), UserID(r.Context()), r.PathValue("id")); err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
