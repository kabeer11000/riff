package cache

import (
	"sync"
	"time"
)

// JSONEntry is a cached JSON response body + its TTL.
type JSONEntry struct {
	Body      []byte
	ExpiresAt time.Time
}

// JSONCache is an in-memory TTL cache for response bodies keyed by an arbitrary
// string (typically route + params). Used for metadata endpoints that are slow
// to resolve and stable across a session (track info, channel/playlist browse).
//
// ponytail: single-process map guarded by one RWMutex; swap for Redis when you
// run more than one backend instance.
type JSONCache struct {
	mu      sync.RWMutex
	entries map[string]JSONEntry
	stop    chan struct{}
}

func NewJSON() *JSONCache {
	c := &JSONCache{
		entries: make(map[string]JSONEntry),
		stop:    make(chan struct{}),
	}
	go c.jsonSweepLoop()
	return c
}

// Get returns a fresh entry, or ok=false if missing or expired.
func (c *JSONCache) Get(k string) (JSONEntry, bool) {
	c.mu.RLock()
	e, ok := c.entries[k]
	c.mu.RUnlock()
	if !ok || time.Now().After(e.ExpiresAt) {
		return JSONEntry{}, false
	}
	return e, true
}

// Set stores an entry.
func (c *JSONCache) Set(k string, e JSONEntry) {
	c.mu.Lock()
	c.entries[k] = e
	c.mu.Unlock()
}

// Close stops the background sweeper.
func (c *JSONCache) Close() { close(c.stop) }

func (c *JSONCache) jsonSweepLoop() {
	t := time.NewTicker(time.Minute)
	defer t.Stop()
	for {
		select {
		case <-c.stop:
			return
		case <-t.C:
			c.jsonSweep()
		}
	}
}

func (c *JSONCache) jsonSweep() {
	now := time.Now()
	c.mu.Lock()
	for k, e := range c.entries {
		if now.After(e.ExpiresAt) {
			delete(c.entries, k)
		}
	}
	c.mu.Unlock()
}