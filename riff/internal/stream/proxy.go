package stream

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"time"
)

// client is used for upstream googlevideo fetches. No redirect surprises, a
// generous timeout for long streams handled via request context instead.
var client = &http.Client{}

// Fetch performs the upstream GET (forwarding the client's Range header) and
// returns the raw response for the caller to inspect before committing to
// write it back to the client — lets a caller try a fallback URL on a 403
// without having already written headers to w. The caller owns resp.Body and
// must close it (Serve does this for it).
func Fetch(ctx context.Context, r *http.Request, upstreamURL string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, upstreamURL, nil)
	if err != nil {
		return nil, err
	}
	if rng := r.Header.Get("Range"); rng != "" {
		req.Header.Set("Range", rng)
	}

	start := time.Now()
	resp, err := client.Do(req)
	elapsed := time.Since(start)
	if err != nil {
		slog.Warn("stream: upstream fetch failed", "url", upstreamURL, "elapsed", elapsed, "err", err)
		return nil, err
	}
	slog.Info("stream: upstream", "url", upstreamURL, "status", resp.StatusCode, "elapsed", elapsed, "bytes", resp.ContentLength, "ctype", resp.Header.Get("Content-Type"), "range", req.Header.Get("Range"))
	return resp, nil
}

// Serve writes an already-fetched upstream response to w, copying the
// relevant headers and status (200 or 206). Closes resp.Body.
func Serve(w http.ResponseWriter, resp *http.Response, contentType string) {
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

// Ok reports whether an upstream response is a usable media response (as
// opposed to a 403/404/etc from a resolved-but-blocked URL).
func Ok(resp *http.Response) bool {
	return resp.StatusCode == http.StatusOK || resp.StatusCode == http.StatusPartialContent
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
