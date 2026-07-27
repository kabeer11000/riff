package httpapi

import (
	"errors"
	"net/http"
	"strconv"

	"riff/m/internal/domain"
	"riff/m/internal/store"
)

func (s *Server) handleListHistory(w http.ResponseWriter, r *http.Request) {
	userID := UserID(r.Context())
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))

	entries, err := s.repo.ListHistory(r.Context(), userID, limit)
	if err != nil {
		writeStoreError(w, err)
		return
	}

	// Continue card is optional; absence is fine.
	card, err := s.repo.LatestContinueCard(r.Context(), userID)
	cardPtr := &card
	if errors.Is(err, store.ErrNotFound) {
		cardPtr = nil
	} else if err != nil {
		writeStoreError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"entries":  entries,
		"continue": cardPtr,
	})
}

func (s *Server) handleRecordPlay(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ItemID       string  `json:"itemId"`
		Title        string  `json:"title"`
		Uploader     string  `json:"uploader"`
		Duration     float64 `json:"duration"`
		Thumbnail    string  `json:"thumbnail"`
		Position     float64 `json:"position"`
		ContextKind  string  `json:"contextKind"`
		ContextID    string  `json:"contextId"`
		ContextTitle string  `json:"contextTitle"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if body.ItemID == "" {
		writeError(w, http.StatusBadRequest, "itemId is required")
		return
	}
	// Verify item exists; copy canonical metadata into the denormalized columns
	// so /me/history reads are a single query.
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
	err = s.repo.RecordPlay(r.Context(), UserID(r.Context()), domain.PlayEvent{
		ItemID:       body.ItemID,
		Title:        body.Title,
		Uploader:     body.Uploader,
		Duration:     body.Duration,
		Thumbnail:    body.Thumbnail,
		Position:     body.Position,
		ContextKind:  body.ContextKind,
		ContextID:    body.ContextID,
		ContextTitle: body.ContextTitle,
	})
	if err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleDeleteHistoryTrack(w http.ResponseWriter, r *http.Request) {
	if err := s.repo.DeleteHistoryTrack(r.Context(), UserID(r.Context()), r.PathValue("itemId")); err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleClearHistory(w http.ResponseWriter, r *http.Request) {
	if err := s.repo.ClearHistory(r.Context(), UserID(r.Context())); err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}