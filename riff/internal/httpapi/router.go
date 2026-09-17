package httpapi

import (
	"net/http"

	"riff/m/internal/cache"
	"riff/m/internal/config"
	"riff/m/internal/index"
	"riff/m/internal/provider"
	"riff/m/internal/store"
	"riff/m/internal/ytdl"
)

// Server holds handler dependencies.
type Server struct {
	cfg       config.Config
	repo      store.Repository
	meta           ytdl.Source         // search/resolve/playlist/channel — swappable (real ytdl or php relay)
	stream         ytdl.StreamResolver // stream URL resolution — tried first
	streamFallback ytdl.StreamResolver // tried if stream resolves a URL that turns out to 403 on fetch; nil = no fallback
	providers      *provider.Registry
	indexer        *index.Indexer
	cache          *cache.URLCache  // resolved googlevideo stream URLs (short TTL)
	jsonCache      *cache.JSONCache // JSON response bodies (longer TTL)
}

func NewServer(cfg config.Config, repo store.Repository, meta ytdl.Source, stream, streamFallback ytdl.StreamResolver, regs *provider.Registry, ix *index.Indexer, c *cache.URLCache, jc *cache.JSONCache) *Server {
	return &Server{cfg: cfg, repo: repo, meta: meta, stream: stream, streamFallback: streamFallback, providers: regs, indexer: ix, cache: c, jsonCache: jc}
}

// Handler builds the fully-wired http.Handler (routes + middleware chain).
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()

	// Public.
	mux.HandleFunc("GET /health", s.handleHealth)
	mux.HandleFunc("GET /search", s.handleSearch)
	mux.HandleFunc("GET /items/{id}", s.handleGetItem)
	mux.HandleFunc("GET /items/{id}/stream", s.handleStreamItem)
	mux.HandleFunc("GET /resolve", s.handleResolveURL)
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
	mux.HandleFunc("DELETE /playlists/{id}/tracks/{itemId}", s.handleRemoveTrack)
	mux.HandleFunc("PUT /playlists/{id}/tracks/order", s.handleReorderTracks)
	mux.HandleFunc("POST /playlists/{id}/share", s.handleShare)

	mux.HandleFunc("GET /me/library/tracks", s.handleListLikes)
	mux.HandleFunc("POST /me/library/tracks", s.handleLike)
	mux.HandleFunc("DELETE /me/library/tracks/{itemId}", s.handleUnlike)
	mux.HandleFunc("POST /me/library/playlists/{id}", s.handleSavePlaylist)
	mux.HandleFunc("DELETE /me/library/playlists/{id}", s.handleUnsavePlaylist)

	// Listening history.
	mux.HandleFunc("GET /me/history/tracks", s.handleListHistory)
	mux.HandleFunc("POST /me/history/tracks", s.handleRecordPlay)
	mux.HandleFunc("DELETE /me/history/tracks/{itemId}", s.handleDeleteHistoryTrack)
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
