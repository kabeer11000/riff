package proxy

import (
	"bufio"
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const defaultListURL = "https://raw.githubusercontent.com/hookzof/socks5_list/master/proxy.txt"

const (
	// After Next() hands a proxy out, the pool won't hand the same one out
	// again until this elapses. Time-based throttle: spreads YouTube's view
	// of our traffic across the list so no single proxy gets hammered.
	minReuseInterval = 5 * time.Second

	// MarkFailed() drops a proxy from rotation for this long.
	failCooldown = 10 * time.Minute

	// How often to re-fetch the list in the background.
	refreshInterval = 15 * time.Minute

	// How long the initial fetch is allowed to take before we give up.
	fetchTimeout = 30 * time.Second
)

// Pool rotates through a SOCKS5 proxy list. Callers pull the next proxy via
// Next(); the pool skips anything in its cooldown window (recently used or
// recently failed). The list refreshes in the background.
type Pool struct {
	url string

	mu      sync.RWMutex
	proxies []string
	cursor  atomic.Uint64

	cooldown sync.Map // proxy string -> time.Time when cooldown expires
}

func NewPool(url string) *Pool {
	if url == "" {
		url = defaultListURL
	}
	p := &Pool{url: url}
	ctx, cancel := context.WithTimeout(context.Background(), fetchTimeout)
	defer cancel()
	if err := p.Refresh(ctx); err != nil {
		slog.Warn("proxy: initial fetch failed", "err", err)
	} else {
		slog.Info("proxy: ready", "url", url)
	}
	go p.loop()
	return p
}

// Next returns a SOCKS5 URL like "socks5://1.2.3.4:1080", or "" if the pool
// is empty or every proxy is cooling down. Returning "" lets the caller
// fall back to a direct connection rather than failing.
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

// Refresh reloads the proxy list. Each non-empty, non-comment line is one
// proxy in `ip:port` form; we prefix with the SOCKS5 scheme.
func (p *Pool) Refresh(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, p.url, nil)
	if err != nil {
		return err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("status %d", resp.StatusCode)
	}
	var proxies []string
	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		proxies = append(proxies, "socks5://"+line)
	}
	if err := scanner.Err(); err != nil {
		return err
	}
	if len(proxies) == 0 {
		return fmt.Errorf("list empty")
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
		ctx, cancel := context.WithTimeout(context.Background(), fetchTimeout)
		if err := p.Refresh(ctx); err != nil {
			slog.Warn("proxy: refresh failed", "err", err)
		}
		cancel()
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