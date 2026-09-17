package stream

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestOk(t *testing.T) {
	cases := []struct {
		status int
		want   bool
	}{
		{http.StatusOK, true},
		{http.StatusPartialContent, true},
		{http.StatusForbidden, false},
		{http.StatusNotFound, false},
	}
	for _, c := range cases {
		resp := &http.Response{StatusCode: c.status}
		if got := Ok(resp); got != c.want {
			t.Errorf("Ok(status=%d) = %v, want %v", c.status, got, c.want)
		}
	}
}

func TestFetchForwardsRange(t *testing.T) {
	var gotRange string
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotRange = r.Header.Get("Range")
		w.WriteHeader(http.StatusPartialContent)
		_, _ = w.Write([]byte("chunk"))
	}))
	defer upstream.Close()

	r := httptest.NewRequest(http.MethodGet, "/items/x/stream", nil)
	r.Header.Set("Range", "bytes=0-1023")

	resp, err := Fetch(r.Context(), r, upstream.URL)
	if err != nil {
		t.Fatalf("Fetch() error = %v", err)
	}
	defer resp.Body.Close()

	if gotRange != "bytes=0-1023" {
		t.Errorf("upstream saw Range = %q, want %q", gotRange, "bytes=0-1023")
	}
	if !Ok(resp) {
		t.Errorf("Ok(resp) = false, want true for status %d", resp.StatusCode)
	}
}

func TestFetchSurfacesForbidden(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusForbidden)
	}))
	defer upstream.Close()

	r := httptest.NewRequest(http.MethodGet, "/items/x/stream", nil)
	resp, err := Fetch(r.Context(), r, upstream.URL)
	if err != nil {
		t.Fatalf("Fetch() error = %v", err)
	}
	defer resp.Body.Close()

	if Ok(resp) {
		t.Errorf("Ok(resp) = true, want false for a 403 — caller needs this to trigger fallback")
	}
}
