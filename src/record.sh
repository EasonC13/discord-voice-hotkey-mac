#!/bin/bash
set -euo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
FFMPEG="$(command -v ffmpeg || true)"

if [[ -z "$FFMPEG" ]]; then
  printf '%s\n' "ffmpeg not found. Install it with: brew install ffmpeg" >&2
  exit 127
fi

OUTPUT="${1:?output MP3 path is required}"
mkdir -p "$(dirname "$OUTPUT")"

# exec is important: Hammerspoon's SIGTERM reaches ffmpeg so it finalizes MP3.
exec "$FFMPEG" \
  -hide_banner -loglevel error \
  -f avfoundation -i ":default" \
  -vn -ac 1 -ar 44100 \
  -codec:a libmp3lame -b:a 96k \
  -y "$OUTPUT"
