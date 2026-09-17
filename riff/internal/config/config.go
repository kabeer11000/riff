package config

import (
	"os"
	"strconv"
	"time"
)

// Config holds runtime configuration, all sourced from environment variables.
type Config struct {
	Port                string // HTTP listen port
	TursoURL            string // libSQL database URL (e.g. libsql://riff-xxx.turso.io)
	TursoToken          string // libSQL auth token
	YTDLPPath           string // path to yt-dlp/youtube-dl binary; empty = look up on PATH
	YTDLPCookiesFile    string // path to Netscape cookies.txt; empty = no cookies
	YTDLPCookiesContent string // if set, written to YTDLPCookiesFile at startup — lets Render's persistent disk get a cookies file via env var instead of shell access
	ProxyListURL        string // path to proxy JSON file; empty disables proxy rotation
	ScraperBackend      string // "ytdlp" (default) or "php" — backs search/resolve/playlist/channel
	PHPScraperURL       string // base URL of the PHP relay (e.g. https://xxx.rf.gd/phprelay); required if ScraperBackend=php

	CacheMaxTTL      time.Duration // ceiling for cached resolved stream URLs (googlevideo)
	CacheMetadataTTL time.Duration // metadata responses (tracks, channels, external playlists) — stable
	CacheSearchTTL   time.Duration // search results — churn more
	PublicBaseURL    string        // base URL used when building shareable links
	RedisURL         string        // optional; not used yet, will host recd:embeddings queue later
}

func Load() Config {
	return Config{
		Port:                env("PORT", "8080"),
		TursoURL:            env("TURSO_DATABASE_URL", ""),
		TursoToken:          env("TURSO_AUTH_TOKEN", ""),
		YTDLPPath:           env("YTDLP_PATH", ""),
		YTDLPCookiesFile:    env("YTDLP_COOKIES_FILE", "/data/yt-cookies.txt"),
		YTDLPCookiesContent: env("YTDLP_COOKIES_CONTENT", ""),
		ProxyListURL:        env("PROXY_LIST_URL", "https://raw.githubusercontent.com/proxifly/free-proxy-list/main/proxies/protocols/socks5/data.json"),
		ScraperBackend:      env("SCRAPER_BACKEND", "ytdlp"),
		PHPScraperURL:       env("PHP_SCRAPER_URL", ""),
		CacheMaxTTL:         envDuration("CACHE_MAX_TTL", 5*time.Minute),
		CacheMetadataTTL:    envDuration("CACHE_METADATA_TTL", time.Hour),
		CacheSearchTTL:      envDuration("CACHE_SEARCH_TTL", 5*time.Minute),
		PublicBaseURL:       env("PUBLIC_BASE_URL", "http://localhost:8080"),
		RedisURL:            env("REDIS_URL", ""),
	}
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envDuration(key string, def time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	if d, err := time.ParseDuration(v); err == nil {
		return d
	}
	if secs, err := strconv.Atoi(v); err == nil {
		return time.Duration(secs) * time.Second
	}
	return def
}
