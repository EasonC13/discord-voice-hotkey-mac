#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/Discord Voice Hotkey.app}"
PROCESS_NAME="DiscordVoiceHotkey"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' "App launch smoke tests require macOS." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"
open "$APP"

PID=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  PID="$(pgrep -x "$PROCESS_NAME" | sed -n '1p' || true)"
  [[ -n "$PID" ]] && break
  sleep 1
done

if [[ -z "$PID" ]]; then
  printf '%s\n' "The menu bar app did not remain running." >&2
  exit 1
fi

printf 'Native menu bar app launched successfully (PID %s).\n' "$PID"
kill "$PID"
