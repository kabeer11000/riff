#!/usr/bin/env bash
# Kill the running riff-server (foreground or detached).
cd "$(dirname "$0")"
if [ -f .server.pid ]; then
  pid=$(cat .server.pid)
  if kill "$pid" 2>/dev/null; then
    echo "stopped pid=$pid"
  fi
  rm -f .server.pid
fi
# Fallback: anything still listening by name.
taskkill //F //IM riff-server.exe >/dev/null 2>&1 || pkill -f riff-server >/dev/null 2>&1 || true
