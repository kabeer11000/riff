package proxy

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"golang.org/x/net/proxy"
)

// Default URL is the proxifly SOCKS5 list — refreshed every 15 min.
const defaultProxyURL = "https://raw.githubusercontent.com/proxifly/free-proxy-list/main/proxies/protocols/socks5/data.json"

const (
	// After Next() hands a proxy out, the pool won't hand the same one out
	// again until this elapses. Time-based throttle: spreads YouTube's view
	// of our traffic across the list so no single proxy gets hammered.
	minReuseInterval = 5 * time.Second

	// MarkFailed() drops a proxy from rotation for this long.
	failCooldown = 10 * time.Minute

	// How often to re-read the source in the background.
	refreshInterval = 15 * time.Minute

	// HTTP fetch timeout for URL sources.
	fetchTimeout = 30 * time.Second

	// Per-proxy health check timeout. Short — we just need to know if the
	// proxy can reach YouTube. Anything slower is dead.
	probeTimeout = 5 * time.Second

	// Parallel probe workers. Cap to avoid swamping the network — at 50, this
	// saturated the container's outbound network capacity badly enough that
	// unrelated calls (e.g. Turso) started timing out at the TCP dial stage
	// for the ~15-20min the probe runs after every deploy. Lower trades a
	// longer warm-up for not degrading the rest of the app meanwhile; Next()
	// already falls back to direct-connect while the pool is still loading.
	probeConcurrency = 8

	// What we HEAD through each proxy to verify it's alive and can reach YT.
	probeTarget = "https://www.youtube.com/robots.txt"
)

// proxyEntry accepts both shapes: proxifly's data.json (full `proxy` URL
// already) and the local file (protocol+ip+port only).
type proxyEntry struct {
	Proxy    string `json:"proxy,omitempty"`
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

// NewPool returns immediately; the initial load (which probes every
// candidate and can take minutes against a list of thousands) runs in the
// background so it never blocks server startup. Next() already treats an
// empty pool as "fall back to direct connect", so callers are safe to use
// the pool before the first load completes.
func NewPool(path string) *Pool {
	if path == "" {
		path = defaultProxyURL
	}
	p := &Pool{path: path}
	go func() {
		if err := p.Refresh(context.Background()); err != nil {
			slog.Warn("proxy: initial load failed", "err", err, "path", path)
		} else {
			slog.Info("proxy: ready", "path", path)
		}
		p.loop()
	}()
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

// Refresh reloads proxies from the source (file path or HTTP/HTTPS URL).
// Each entry's protocol becomes the URL scheme (socks5 today); entries
// missing required fields are skipped.
func (p *Pool) Refresh(ctx context.Context) error {
	var data []byte
	var err error
	if isURL(p.path) {
		data, err = fetchURL(ctx, p.path)
	} else {
		data, err = os.ReadFile(p.path)
	}
	if err != nil {
		return err
	}
	var entries []proxyEntry
	if err := json.Unmarshal(data, &entries); err != nil {
		return err
	}
	proxies := make([]string, 0, len(entries))
	for _, e := range entries {
		if e.Proxy != "" {
			proxies = append(proxies, e.Proxy)
			continue
		}
		if e.Protocol != "socks5" || e.IP == "" || e.Port <= 0 {
			continue
		}
		proxies = append(proxies, e.Protocol+"://"+e.IP+":"+strconv.Itoa(e.Port))
	}
	if len(proxies) == 0 {
		return errEmpty{path: p.path}
	}
	slog.Info("proxy: probing", "count", len(proxies))
	alive := p.probe(ctx, proxies)
	if len(alive) == 0 {
		return errEmpty{path: p.path}
	}
	p.mu.Lock()
	p.proxies = alive
	p.mu.Unlock()
	slog.Info("proxy: loaded", "candidates", len(proxies), "alive", len(alive))
	return nil
}

// probe runs a HEAD request through each candidate in parallel and returns
// only the ones that responded successfully. Public proxy lists are mostly
// dead — this filters them out before they hit yt-dlp.
func (p *Pool) probe(ctx context.Context, candidates []string) []string {
	var wg sync.WaitGroup
	var mu sync.Mutex
	alive := make([]string, 0, len(candidates))
	sem := make(chan struct{}, probeConcurrency)
	for _, pr := range candidates {
		sem <- struct{}{}
		wg.Add(1)
		go func(proxyURL string) {
			defer wg.Done()
			defer func() { <-sem }()
			if p.probeOne(ctx, proxyURL) {
				mu.Lock()
				alive = append(alive, proxyURL)
				mu.Unlock()
			}
		}(pr)
	}
	wg.Wait()
	return alive
}

func (p *Pool) probeOne(ctx context.Context, proxyURL string) bool {
	ctx, cancel := context.WithTimeout(ctx, probeTimeout)
	defer cancel()
	u, err := url.Parse(proxyURL)
	if err != nil {
		return false
	}
	dialer, err := proxy.FromURL(u, proxy.Direct)
	if err != nil {
		return false
	}
	tr := &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			return dialer.Dial(network, addr)
		},
	}
	defer tr.CloseIdleConnections()
	client := &http.Client{Transport: tr}
	req, err := http.NewRequestWithContext(ctx, http.MethodHead, probeTarget, nil)
	if err != nil {
		return false
	}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode < 500
}

func isURL(s string) bool {
	return strings.HasPrefix(s, "http://") || strings.HasPrefix(s, "https://")
}

func fetchURL(ctx context.Context, url string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, fetchTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("status %d", resp.StatusCode)
	}
	return io.ReadAll(resp.Body)
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