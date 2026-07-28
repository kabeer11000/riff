package proxy

import (
	"context"
	"encoding/json"
	"log/slog"
	"os"
	"strconv"
	"sync"
	"sync/atomic"
	"time"
)

// Default path is relative to the working directory; the binary runs from
// riff/ in dev and from /app in the Docker image (see Dockerfile).
const defaultProxyFile = "proxylists/proxifly-proxies.json"

const (
	// After Next() hands a proxy out, the pool won't hand the same one out
	// again until this elapses. Time-based throttle: spreads YouTube's view
	// of our traffic across the list so no single proxy gets hammered.
	minReuseInterval = 5 * time.Second

	// MarkFailed() drops a proxy from rotation for this long.
	failCooldown = 10 * time.Minute

	// How often to re-read the file in the background. Cheap; no network.
	refreshInterval = 15 * time.Minute
)

// proxyEntry is the subset of the proxifly JSON shape we read. We could
// consume the full object but we only need protocol+ip+port to build the URL
// yt-dlp expects.
type proxyEntry struct {
	Protocol string `json:"protocol"`
	IP       string `json:"ip"`
	Port     int    `json:"port"`
}

// Pool rotates through a proxy list. Callers pull the next proxy via Next();
// the pool skips anything in its cooldown window (recently used or recently
// failed). The list is reloaded from disk on a background ticker.
type Pool struct {
	path string

	mu      sync.RWMutex
	proxies []string
	cursor  atomic.Uint64

	cooldown sync.Map // proxy string -> time.Time when cooldown expires
}

func NewPool(path string) *Pool {
	if path == "" {
		path = defaultProxyFile
	}
	p := &Pool{path: path}
	if err := p.Refresh(context.Background()); err != nil {
		slog.Warn("proxy: initial load failed", "err", err, "path", path)
	} else {
		slog.Info("proxy: ready", "path", path)
	}
	go p.loop()
	return p
}

// Next returns a URL like "socks5://1.2.3.4:1080" or "http://1.2.3.4:8080",
// or "" if the pool is empty or every proxy is cooling down. Returning ""
// lets the caller fall back to a direct connection rather than failing.
func (p *Pool) Next() string {
	p.mu.RLock()
	defer p.mu.RUnlock()
	if len(p.proxies) == 0 {
		return ""
	}
	n := uint64(len(p.proxies))
	now := time.Now()
	for i := uint64(0); i < n; i++ {
		idx := p.cursor.Add(1) % n
		candidate := p.proxies[idx]
		if p.isCoolingDown(candidate, now) {
			continue
		}
		p.cooldown.Store(candidate, now.Add(minReuseInterval))
		return candidate
	}
	return ""
}

// MarkFailed drops the proxy from rotation for failCooldown. Call when a
// request through that proxy returned a network error.
func (p *Pool) MarkFailed(proxy string) {
	if proxy == "" {
		return
	}
	p.cooldown.Store(proxy, time.Now().Add(failCooldown))
}

// Refresh reloads proxies from the JSON file on disk. Each entry's protocol
// becomes the URL scheme (http / socks4 / socks5); ip:port is appended.
// Entries missing any required field are skipped.
func (p *Pool) Refresh(ctx context.Context) error {
	data, err := os.ReadFile(p.path)
	if err != nil {
		return err
	}
	var entries []proxyEntry
	if err := json.Unmarshal(data, &entries); err != nil {
		return err
	}
	proxies := make([]string, 0, len(entries))
	for _, e := range entries {
		if e.Protocol != "socks5" || e.IP == "" || e.Port <= 0 {
			continue
		}
		proxies = append(proxies, e.Protocol+"://"+e.IP+":"+strconv.Itoa(e.Port))
	}
	if len(proxies) == 0 {
		return errEmpty{path: p.path}
	}
	p.mu.Lock()
	p.proxies = proxies
	p.mu.Unlock()
	slog.Info("proxy: loaded", "count", len(proxies))
	return nil
}

func (p *Pool) loop() {
	ticker := time.NewTicker(refreshInterval)
	defer ticker.Stop()
	for range ticker.C {
		if err := p.Refresh(context.Background()); err != nil {
			slog.Warn("proxy: refresh failed", "err", err)
		}
	}
}

func (p *Pool) isCoolingDown(proxy string, now time.Time) bool {
	v, ok := p.cooldown.Load(proxy)
	if !ok {
		return false
	}
	expiry := v.(time.Time)
	if now.After(expiry) {
		p.cooldown.Delete(proxy)
		return false
	}
	return true
}

type errEmpty struct{ path string }

func (e errEmpty) Error() string { return "proxy: list empty (" + e.path + ")" }