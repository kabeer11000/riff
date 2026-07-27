package httpapi

import "net/http"

func (s *Server) handleGetMe(w http.ResponseWriter, r *http.Request) {
	p, err := s.repo.GetProfile(r.Context(), UserID(r.Context()))
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func (s *Server) handleUpdateMe(w http.ResponseWriter, r *http.Request) {
	var body struct {
		DisplayName string `json:"displayName"`
		AvatarURL   string `json:"avatarUrl"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid body")
		return
	}
	p, err := s.repo.UpdateProfile(r.Context(), UserID(r.Context()), body.DisplayName, body.AvatarURL)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func (s *Server) handleGetUser(w http.ResponseWriter, r *http.Request) {
	p, err := s.repo.GetProfile(r.Context(), r.PathValue("id"))
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func (s *Server) handleGetUserPlaylists(w http.ResponseWriter, r *http.Request) {
	pls, err := s.repo.ListPlaylistsByOwner(r.Context(), r.PathValue("id"), true)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"playlists": pls})
}
