package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"time"

	"riff/m/internal/cache"
	"riff/m/internal/config"
	"riff/m/internal/httpapi"
	"riff/m/internal/index"
	"riff/m/internal/provider"
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

	y := ytdl.New(cfg.YTDLPPath)
	regs := &provider.Registry{Providers: []provider.Provider{provider.NewYouTube(y)}}
	ix := index.New(repo)

	srv := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: httpapi.NewServer(cfg, repo, y, regs, ix, urlCache, jsonCache).Handler(),
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
