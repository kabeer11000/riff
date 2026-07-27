# syntax=docker/dockerfile:1.7
#
# Build context: the riff/ directory (set this as the service rootDir in Render).
# Image layers: 1) yt-dlp binary, 2) Go build, 3) runtime.
# Runtime: Python 3.12 slim + yt-dlp + ffmpeg. The Go server shells out to yt-dlp
# via the wader/goutubedl library; embedded downloads/muxing need ffmpeg in PATH.

ARG GO_VERSION=1.26

# ---- yt-dlp (cached; rarely changes) -------------------------------------
FROM alpine:3.20 AS ytdlp
RUN apk add --no-cache ca-certificates curl \
 && curl -fsSL -o /yt-dlp https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux \
 && chmod +x /yt-dlp \
 && apk del curl \
 && /yt-dlp --version

# ---- Go build ------------------------------------------------------------
FROM golang:${GO_VERSION}-alpine AS builder
WORKDIR /src
ENV CGO_ENABLED=0 GOFLAGS=-mod=readonly
RUN apk add --no-cache git
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -trimpath -ldflags="-s -w" -o /out/riff-server .

# ---- Runtime -------------------------------------------------------------
FROM python:3.12-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates wget ffmpeg \
 && pip install --no-cache-dir --break-system-packages yt-dlp \
 && apt-get clean && rm -rf /var/lib/apt/lists/*
COPY --from=builder /out/riff-server /usr/local/bin/riff-server
RUN useradd --system --uid 1000 --shell /usr/sbin/nologin --no-create-home riff
USER riff
ENV PORT=8080 \
    YTDLP_PATH=/usr/local/bin/yt-dlp \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD wget -qO- "http://127.0.0.1:${PORT}/health" || exit 1
ENTRYPOINT ["/usr/local/bin/riff-server"]
