package httpapi

import (
	"net/http"

	"riff/m/internal/domain"
)

func (s *Server) handleListMyPlaylists(w http.ResponseWriter, r *http.Request) {
	pls, err := s.repo.ListPlaylistsByOwner(r.Context(), UserID(r.Context()), false)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"playlists": pls})
}

func (s *Server) handleCreatePlaylist(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Name        string `json:"name"`
		Description string `json:"description"`
		Visibility  string `json:"visibility"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if body.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	if !validVisibility(body.Visibility) {
		writeError(w, http.StatusBadRequest, "invalid visibility")
		return
	}
	p, err := s.repo.CreatePlaylist(r.Context(), UserID(r.Context()), body.Name, body.Description, body.Visibility)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, p)
}

func (s *Server) handleGetPlaylist(w http.ResponseWriter, r *http.Request) {
	p, err := s.repo.GetPlaylist(r.Context(), r.PathValue("id"))
	if err != nil {
		writeStoreError(w, err)
		return
	}
	// Visibility: owner sees anything; others only if public. Unlisted is
	// reachable only through the /shared/{token} route.
	if p.OwnerID != UserID(r.Context()) && p.Visibility != domain.VisibilityPublic {
		writeError(w, http.StatusForbidden, "forbidden")
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func (s *Server) handleUpdatePlaylist(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Name        string `json:"name"`
		Description string `json:"description"`
		CoverURL    string `json:"coverUrl"`
		Visibility  string `json:"visibility"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if body.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	if !validVisibility(body.Visibility) {
		writeError(w, http.StatusBadRequest, "invalid visibility")
		return
	}
	p, err := s.repo.UpdatePlaylist(r.Context(), r.PathValue("id"), UserID(r.Context()),
		body.Name, body.Description, body.CoverURL, body.Visibility)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func (s *Server) handleDeletePlaylist(w http.ResponseWriter, r *http.Request) {
	if err := s.repo.DeletePlaylist(r.Context(), r.PathValue("id"), UserID(r.Context())); err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleAddTrack(w http.ResponseWriter, r *http.Request) {
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
	t := domain.PlaylistTrack{
		ItemID:    body.ItemID,
		Title:     body.Title,
		Uploader:  body.Uploader,
		Duration:  body.Duration,
		Thumbnail: body.Thumbnail,
	}
	if err := s.repo.AddPlaylistTrack(r.Context(), r.PathValue("id"), UserID(r.Context()), t); err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleRemoveTrack(w http.ResponseWriter, r *http.Request) {
	err := s.repo.RemovePlaylistTrack(r.Context(), r.PathValue("id"), UserID(r.Context()), r.PathValue("itemId"))
	if err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleReorderTracks(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Order []string `json:"order"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid body")
		return
	}
	err := s.repo.ReorderPlaylistTracks(r.Context(), r.PathValue("id"), UserID(r.Context()), body.Order)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func validVisibility(v string) bool {
	switch v {
	case "", domain.VisibilityPublic, domain.VisibilityPrivate, domain.VisibilityUnlisted:
		return true
	}
	return false
}
