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
		VideoID   string  `json:"videoId"`
		Title     string  `json:"title"`
		Uploader  string  `json:"uploader"`
		Duration  float64 `json:"duration"`
		Thumbnail string  `json:"thumbnail"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if body.VideoID == "" {
		writeError(w, http.StatusBadRequest, "videoId is required")
		return
	}
	if body.Title == "" {
		if ti, err := s.ytdl.Resolve(r.Context(), body.VideoID); err == nil {
			body.Title = ti.Title
			body.Uploader = ti.Uploader
			body.Duration = ti.Duration
			body.Thumbnail = ti.Thumbnail
		}
	}
	if body.Thumbnail == "" {
		body.Thumbnail = s.ytdl.Thumbnail(body.VideoID)
	}
	err := s.repo.LikeTrack(r.Context(), UserID(r.Context()), domain.LikedTrack{
		VideoID:   body.VideoID,
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
	if err := s.repo.UnlikeTrack(r.Context(), UserID(r.Context()), r.PathValue("videoId")); err != nil {
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
