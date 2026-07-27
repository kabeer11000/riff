package httpapi

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"riff/m/internal/cache"
	"riff/m/internal/store"
)

// writeJSON encodes v as JSON with the given status.
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if v == nil {
		return
	}
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("encode response", "err", err)
	}
}

// writeCachedJSON serves a cached JSON body when fresh, otherwise marshals v,
// stores it, and writes. On a hit, the Cache-Control max-age is the actual
// remaining TTL so clients/CDNs don't cache past freshness.
func (s *Server) writeCachedJSON(w http.ResponseWriter, key string, ttl time.Duration, v any) {
	if e, ok := s.jsonCache.Get(key); ok {
		remaining := int(time.Until(e.ExpiresAt).Seconds())
		if remaining < 0 {
			remaining = 0
		}
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Cache-Control", "public, max-age="+strconv.Itoa(remaining))
		w.Header().Set("X-Cache", "HIT")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(e.Body)
		return
	}
	body, err := json.Marshal(v)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "encode failed")
		return
	}
	s.jsonCache.Set(key, cache.JSONEntry{Body: body, ExpiresAt: time.Now().Add(ttl)})
	secs := int(ttl.Seconds())
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age="+strconv.Itoa(secs))
	w.Header().Set("X-Cache", "MISS")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(body)
}

// writeError writes a JSON error envelope: {"error": "..."}.
func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

// writeStoreError maps store errors to HTTP status codes.
func writeStoreError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "not found")
	case errors.Is(err, store.ErrForbidden):
		writeError(w, http.StatusForbidden, "forbidden")
	default:
		slog.Error("store error", "err", err)
		writeError(w, http.StatusInternalServerError, "internal error")
	}
}

// decodeJSON reads a JSON request body into v, capping the body size.
func decodeJSON(r *http.Request, v any) error {
	dec := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 1<<20))
	dec.DisallowUnknownFields()
	return dec.Decode(v)
}
