package httpapi

import (
	"net/http"

	"riff/m/internal/cache"
	"riff/m/internal/config"
	"riff/m/internal/store"
	"riff/m/internal/ytdl"
)

// Server holds handler dependencies.
type Server struct {
	cfg       config.Config
	repo      store.Repository
	ytdl      *ytdl.Client
	cache     *cache.URLCache  // resolved googlevideo stream URLs (short TTL)
	jsonCache *cache.JSONCache // JSON response bodies (longer TTL)
}

func NewServer(cfg config.Config, repo store.Repository, y *ytdl.Client, c *cache.URLCache, jc *cache.JSONCache) *Server {
	return &Server{cfg: cfg, repo: repo, ytdl: y, cache: c, jsonCache: jc}
}

// Handler builds the fully-wired http.Handler (routes + middleware chain).
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()

	// Public.
	mux.HandleFunc("GET /health", s.handleHealth)
	mux.HandleFunc("GET /search", s.handleSearch)
	mux.HandleFunc("GET /tracks/{id}", s.handleGetTrack)
	mux.HandleFunc("GET /tracks/{id}/stream", s.handleStream)
	mux.HandleFunc("GET /yt/playlists/{id}", s.handleYTPlaylist)
	mux.HandleFunc("GET /yt/channels/{id}", s.handleYTChannel)
	mux.HandleFunc("GET /users/{id}", s.handleGetUser)
	mux.HandleFunc("GET /users/{id}/playlists", s.handleGetUserPlaylists)
	mux.HandleFunc("GET /shared/{token}", s.handleGetShared)

	// Identity-scoped (X-User-Id). Identity middleware is applied globally, so
	// these read the caller via UserID(ctx).
	mux.HandleFunc("GET /me", s.handleGetMe)
	mux.HandleFunc("PUT /me", s.handleUpdateMe)
	mux.HandleFunc("GET /me/playlists", s.handleListMyPlaylists)

	mux.HandleFunc("POST /playlists", s.handleCreatePlaylist)
	mux.HandleFunc("GET /playlists/{id}", s.handleGetPlaylist)
	mux.HandleFunc("PUT /playlists/{id}", s.handleUpdatePlaylist)
	mux.HandleFunc("DELETE /playlists/{id}", s.handleDeletePlaylist)
	mux.HandleFunc("POST /playlists/{id}/tracks", s.handleAddTrack)
	mux.HandleFunc("DELETE /playlists/{id}/tracks/{videoId}", s.handleRemoveTrack)
	mux.HandleFunc("PUT /playlists/{id}/tracks/order", s.handleReorderTracks)
	mux.HandleFunc("POST /playlists/{id}/share", s.handleShare)

	mux.HandleFunc("GET /me/library/tracks", s.handleListLikes)
	mux.HandleFunc("POST /me/library/tracks", s.handleLike)
	mux.HandleFunc("DELETE /me/library/tracks/{videoId}", s.handleUnlike)
	mux.HandleFunc("POST /me/library/playlists/{id}", s.handleSavePlaylist)
	mux.HandleFunc("DELETE /me/library/playlists/{id}", s.handleUnsavePlaylist)

	// Listening history.
	mux.HandleFunc("GET /me/history/tracks", s.handleListHistory)
	mux.HandleFunc("POST /me/history/tracks", s.handleRecordPlay)
	mux.HandleFunc("DELETE /me/history/tracks/{videoId}", s.handleDeleteHistoryTrack)
	mux.HandleFunc("DELETE /me/history/tracks", s.handleClearHistory)

	// Middleware chain (outermost first).
	var h http.Handler = mux
	h = Identity(s.repo.EnsureUser)(h)
	h = CORS(h)
	h = Logging(h)
	h = Recover(h)
	return h
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
