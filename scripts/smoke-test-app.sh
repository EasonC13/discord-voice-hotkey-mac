#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${1:-$(find "$ROOT/dist" -maxdepth 1 -name 'Discord-Voice-Hotkey-*.dmg' -print -quit)}"
PROCESS_NAME="DiscordVoiceHotkey"
MOUNT_POINT="$(mktemp -d)"

cleanup() {
  pkill -x "$PROCESS_NAME" 2>/dev/null || true
  hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
  rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' "App launch smoke tests require macOS." >&2
  exit 1
fi

if [[ -z "$DMG" || ! -f "$DMG" ]]; then
  printf '%s\n' "No built DMG was found." >&2
  exit 1
fi

hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$DMG" >/dev/null
APP="$MOUNT_POINT/Discord Voice Hotkey.app"

[[ -d "$APP" ]]
[[ -L "$MOUNT_POINT/Applications" ]]
[[ "$(readlink "$MOUNT_POINT/Applications")" == "/Applications" ]]
codesign --verify --deep --strict --verbose=2 "$APP"
open "$APP"

PID=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  PID="$(pgrep -x "$PROCESS_NAME" | sed -n '1p' || true)"
  [[ -n "$PID" ]] && break
  sleep 1
done

if [[ -z "$PID" ]]; then
  printf '%s\n' "The menu bar app from the mounted DMG did not remain running." >&2
  exit 1
fi

printf 'Mounted DMG app launched successfully (PID %s).\n' "$PID"
