package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"time"

	"riff/m/internal/cache"
	"riff/m/internal/config"
	"riff/m/internal/httpapi"
	"riff/m/internal/index"
	"riff/m/internal/phpscraper"
	"riff/m/internal/provider"
	"riff/m/internal/proxy"
	"riff/m/internal/store"
	"riff/m/internal/ytdl"
)

func main() {
	cfg := config.Load()

	repo, err := store.OpenTurso(cfg.TursoURL, cfg.TursoToken)
	if err != nil {
		slog.Error("open turso", "err", err)
		os.Exit(1)
	}
	defer repo.Close()

	urlCache := cache.New()
	defer urlCache.Close()

	jsonCache := cache.NewJSON()
	defer jsonCache.Close()

	if cfg.YTDLPCookiesContent != "" {
		if err := writeCookiesFile(cfg.YTDLPCookiesFile, cfg.YTDLPCookiesContent); err != nil {
			slog.Error("write cookies file", "path", cfg.YTDLPCookiesFile, "err", err)
			os.Exit(1)
		}
		slog.Info("wrote yt-dlp cookies file from YTDLP_COOKIES_CONTENT", "path", cfg.YTDLPCookiesFile)
	}

	var proxyPool *proxy.Pool
	if cfg.ProxyListURL != "" {
		proxyPool = proxy.NewPool(cfg.ProxyListURL)
	}
	y := ytdl.New(cfg.YTDLPPath, cfg.YTDLPCookiesFile, proxyPool)

	// meta backs search/resolve/playlist/channel; stream backs stream URL
	// resolution. Both swap to the PHP relay together: it resolves streams
	// via an InnerTube client context that returns unciphered URLs, which
	// matters on hosts like Render where yt-dlp's own IP gets blocked.
	//
	// streamFallback stays yt-dlp even when php is primary: YouTube enforces
	// a proof-of-origin token requirement on the ANDROID client per-video,
	// seemingly inconsistently, so a resolved php URL can still 403 on fetch.
	// Falling back to yt-dlp (with its own proxy pool) catches those.
	var meta ytdl.Source = y
	var stream ytdl.StreamResolver = y
	var streamFallback ytdl.StreamResolver
	if cfg.ScraperBackend == "php" {
		if cfg.PHPScraperURL == "" {
			slog.Error("SCRAPER_BACKEND=php requires PHP_SCRAPER_URL")
			os.Exit(1)
		}
		php := phpscraper.New(cfg.PHPScraperURL)
		meta = php
		stream = php
		streamFallback = y
		slog.Info("scraper backend: php", "url", cfg.PHPScraperURL)
	}

	regs := &provider.Registry{Providers: []provider.Provider{provider.NewYouTube(meta)}}
	ix := index.New(repo)

	srv := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: httpapi.NewServer(cfg, repo, meta, stream, streamFallback, regs, ix, urlCache, jsonCache).Handler(),
	}

	go func() {
		slog.Info("listening", "addr", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("server", "err", err)
			os.Exit(1)
		}
	}()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	<-ctx.Done()

	slog.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdownCtx)
}

// writeCookiesFile writes content to path, creating parent directories as
// needed (Render's persistent disk mounts empty, so /data itself may not
// exist yet on first boot).
func writeCookiesFile(path, content string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(content), 0o600)
}
