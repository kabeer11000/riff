package cache

import (
	"testing"
	"time"
)

func TestJSONGetSetExpiry(t *testing.T) {
	c := NewJSON()
	t.Cleanup(c.Close)

	c.Set("k1", JSONEntry{Body: []byte(`{"a":1}`), ExpiresAt: time.Now().Add(time.Hour)})
	got, ok := c.Get("k1")
	if !ok {
		t.Fatal("expected hit")
	}
	if string(got.Body) != `{"a":1}` {
		t.Fatalf("body=%q", got.Body)
	}
}

func TestJSONGetExpired(t *testing.T) {
	c := NewJSON()
	t.Cleanup(c.Close)

	c.Set("k1", JSONEntry{Body: []byte(`{}`), ExpiresAt: time.Now().Add(-time.Second)})
	if _, ok := c.Get("k1"); ok {
		t.Fatal("expected expired entry to miss")
	}
}

func TestJSONSweepRemovesExpired(t *testing.T) {
	c := &JSONCache{entries: make(map[string]JSONEntry), stop: make(chan struct{})}
	defer close(c.stop)

	c.entries["old"] = JSONEntry{Body: []byte(`{}`), ExpiresAt: time.Now().Add(-time.Minute)}
	c.entries["fresh"] = JSONEntry{Body: []byte(`{}`), ExpiresAt: time.Now().Add(time.Hour)}

	c.jsonSweep()

	if _, ok := c.entries["old"]; ok {
		t.Fatal("expected expired entry swept")
	}
	if _, ok := c.entries["fresh"]; !ok {
		t.Fatal("expected fresh entry kept")
	}
}