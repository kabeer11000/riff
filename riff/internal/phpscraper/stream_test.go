package phpscraper

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestResolveStream(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/stream.php" {
			t.Fatalf("unexpected path %q", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"url":"https://example.com/audio?expire=1700000000","mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","expiresAt":1700000000}`))
	}))
	defer srv.Close()

	c := New(srv.URL)
	rs, err := c.ResolveStream(context.Background(), "abc123", "audio")
	if err != nil {
		t.Fatalf("ResolveStream() error = %v", err)
	}
	if rs.URL != "https://example.com/audio?expire=1700000000" {
		t.Errorf("URL = %q", rs.URL)
	}
	if rs.ContentType != "audio/mp4" {
		t.Errorf("ContentType = %q, want %q (mimeType params should be stripped)", rs.ContentType, "audio/mp4")
	}
	if !rs.ExpiresAt.Equal(time.Unix(1700000000, 0)) {
		t.Errorf("ExpiresAt = %v", rs.ExpiresAt)
	}
}

func TestResolveStreamNoURL(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"error":"not playable: ERROR"}`))
	}))
	defer srv.Close()

	c := New(srv.URL)
	_, err := c.ResolveStream(context.Background(), "abc123", "audio")
	if err == nil {
		t.Fatal("ResolveStream() error = nil, want error for missing url")
	}
}
