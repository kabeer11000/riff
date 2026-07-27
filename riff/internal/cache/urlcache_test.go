package cache

import (
	"testing"
	"time"
)

func TestGetSetExpiry(t *testing.T) {
	c := New()
	t.Cleanup(c.Close)

	c.Set("vid", "audio", Entry{URL: "https://g/1", ContentType: "audio/mp4", ExpiresAt: time.Now().Add(time.Hour)})

	got, ok := c.Get("vid", "audio")
	if !ok {
		t.Fatal("expected hit")
	}
	if got.URL != "https://g/1" {
		t.Fatalf("got url %q want %q", got.URL, "https://g/1")
	}

	if _, ok := c.Get("missing", "audio"); ok {
		t.Fatal("expected miss on missing key")
	}
}

func TestGetExpired(t *testing.T) {
	c := New()
	t.Cleanup(c.Close)

	c.Set("vid", "audio", Entry{URL: "https://g/1", ExpiresAt: time.Now().Add(-time.Second)})
	if _, ok := c.Get("vid", "audio"); ok {
		t.Fatal("expected expired entry to miss")
	}
}

func TestSweepRemovesExpired(t *testing.T) {
	c := &URLCache{entries: make(map[string]Entry), stop: make(chan struct{})}
	defer close(c.stop)

	c.entries[key("old", "audio")] = Entry{URL: "u", ExpiresAt: time.Now().Add(-time.Minute)}
	c.entries[key("fresh", "audio")] = Entry{URL: "u", ExpiresAt: time.Now().Add(time.Hour)}

	c.sweep()

	if _, ok := c.entries[key("old", "audio")]; ok {
		t.Fatal("expected expired entry to be swept")
	}
	if _, ok := c.entries[key("fresh", "audio")]; !ok {
		t.Fatal("expected fresh entry to remain")
	}
}

func TestKeyIsolation(t *testing.T) {
	if key("a", "b") == key("a|b", "") {
		t.Fatal("key collision risk")
	}
	if key("abc", "audio") != "abc|audio" {
		t.Fatal("key format unexpected")
	}
}