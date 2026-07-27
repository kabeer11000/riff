package cache

import (
	"sync"
	"time"
)

// Entry is a cached resolved stream URL with its expiry and content type.
type Entry struct {
	URL         string
	ContentType string
	ExpiresAt   time.Time
}

// URLCache is an in-memory TTL cache for resolved googlevideo URLs, keyed by
// videoID+kind. Resolved URLs are short-lived (a googlevideo URL carries an
// `expire` param), so entries are evicted on read and by a background sweep.
//
// ponytail: single-process map guarded by one RWMutex; swap for Redis when you
// run more than one backend instance.
type URLCache struct {
	mu      sync.RWMutex
	entries map[string]Entry
	stop    chan struct{}
}

func New() *URLCache {
	c := &URLCache{
		entries: make(map[string]Entry),
		stop:    make(chan struct{}),
	}
	go c.sweepLoop()
	return c
}

func key(videoID, kind string) string { return videoID + "|" + kind }

// Get returns a fresh entry, or ok=false if missing or expired.
func (c *URLCache) Get(videoID, kind string) (Entry, bool) {
	c.mu.RLock()
	e, ok := c.entries[key(videoID, kind)]
	c.mu.RUnlock()
	if !ok || time.Now().After(e.ExpiresAt) {
		return Entry{}, false
	}
	return e, true
}

// Set stores an entry.
func (c *URLCache) Set(videoID, kind string, e Entry) {
	c.mu.Lock()
	c.entries[key(videoID, kind)] = e
	c.mu.Unlock()
}

// Close stops the background sweeper.
func (c *URLCache) Close() { close(c.stop) }

func (c *URLCache) sweepLoop() {
	t := time.NewTicker(time.Minute)
	defer t.Stop()
	for {
		select {
		case <-c.stop:
			return
		case <-t.C:
			c.sweep()
		}
	}
}

func (c *URLCache) sweep() {
	now := time.Now()
	c.mu.Lock()
	for k, e := range c.entries {
		if now.After(e.ExpiresAt) {
			delete(c.entries, k)
		}
	}
	c.mu.Unlock()
}
