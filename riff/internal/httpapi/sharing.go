package httpapi

import (
	"crypto/rand"
	"encoding/base32"
	"net/http"
)

func (s *Server) handleShare(w http.ResponseWriter, r *http.Request) {
	token := shareToken()
	p, err := s.repo.SetShareToken(r.Context(), r.PathValue("id"), UserID(r.Context()), token)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"token": p.ShareToken,
		"url":   s.cfg.PublicBaseURL + "/shared/" + p.ShareToken,
	})
}

func (s *Server) handleGetShared(w http.ResponseWriter, r *http.Request) {
	p, err := s.repo.GetPlaylistByShareToken(r.Context(), r.PathValue("token"))
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func shareToken() string {
	b := make([]byte, 15)
	_, _ = rand.Read(b)
	return base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(b)
}
