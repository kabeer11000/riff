#!/usr/bin/env bash
# Same as run.sh, but launches in the background and tails server.log.
# Use ./stop.sh to kill it.
set -e
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "missing .env (copy from .env.example and fill in TURSO_* + YTDLP_PATH)" >&2
  exit 1
fi
set -a
# shellcheck disable=SC1091
. ./.env
set +a
if [ -z "${TURSO_DATABASE_URL:-}" ]; then
  echo "TURSO_DATABASE_URL is empty in .env" >&2
  exit 1
fi

: > server.log
nohup ./riff-server >> server.log 2>&1 &
echo $! > .server.pid
sleep 2
echo "started pid=$(cat .server.pid) on :${PORT:-8080}"
echo "tail server.log with: tail -f server.log"
