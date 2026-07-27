#!/usr/bin/env bash
# Source .env into the current shell, then start riff-server.
# Stops on missing .env so you don't accidentally boot a server with empty
# Turso creds.
set -e
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "missing .env (copy from .env.example and fill in TURSO_* + YTDLP_PATH)" >&2
  exit 1
fi

# shellcheck disable=SC2046
export $(grep -v '^#' .env | xargs)

if [ -z "${TURSO_DATABASE_URL:-}" ]; then
  echo "TURSO_DATABASE_URL is empty in .env" >&2
  exit 1
fi

echo "starting on :${PORT:-8080} (db=${TURSO_DATABASE_URL})"
exec ./riff-server
