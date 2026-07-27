package stream

import (
	"context"
	"io"
	"net/http"
)

// client is used for upstream googlevideo fetches. No redirect surprises, a
// generous timeout for long streams handled via request context instead.
var client = &http.Client{}

// Proxy fetches upstreamURL and streams it back to w, forwarding the client's
// Range header so seeking works. It copies the relevant response headers and
// status (200 or 206) from upstream.
func Proxy(ctx context.Context, w http.ResponseWriter, r *http.Request, upstreamURL, contentType string) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, upstreamURL, nil)
	if err != nil {
		http.Error(w, "bad upstream url", http.StatusBadGateway)
		return
	}
	if rng := r.Header.Get("Range"); rng != "" {
		req.Header.Set("Range", rng)
	}

	resp, err := client.Do(req)
	if err != nil {
		http.Error(w, "upstream fetch failed", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	h := w.Header()
	copyHeader(h, resp.Header, "Content-Range")
	copyHeader(h, resp.Header, "Content-Length")
	copyHeader(h, resp.Header, "Accept-Ranges")
	if ct := resp.Header.Get("Content-Type"); ct != "" {
		h.Set("Content-Type", ct)
	} else if contentType != "" {
		h.Set("Content-Type", contentType)
	}
	if h.Get("Accept-Ranges") == "" {
		h.Set("Accept-Ranges", "bytes")
	}

	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
}

func copyHeader(dst, src http.Header, key string) {
	if v := src.Get(key); v != "" {
		dst.Set(key, v)
	}
}

// Pipe streams from an arbitrary reader (the yt-dlp fallback path) without Range
// support. Used when no directly-proxyable format exists.
func Pipe(w http.ResponseWriter, rc io.ReadCloser, contentType string) {
	defer rc.Close()
	if contentType != "" {
		w.Header().Set("Content-Type", contentType)
	}
	w.WriteHeader(http.StatusOK)
	_, _ = io.Copy(w, rc)
}
