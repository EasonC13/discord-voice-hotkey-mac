#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${1:-$(find "$ROOT/dist" -maxdepth 1 -name 'Discord-Voice-Hotkey-*.dmg' -print -quit)}"
PROCESS_NAME="DiscordVoiceHotkey"
MOUNT_POINT="$(mktemp -d)"
INSTALL_ROOT="$(mktemp -d)"

cleanup() {
  pkill -x "$PROCESS_NAME" 2>/dev/null || true
  hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
  rmdir "$MOUNT_POINT" 2>/dev/null || true
  rm -rf -- "$INSTALL_ROOT"
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

if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
  printf '%s\n' "A pre-existing $PROCESS_NAME process would invalidate the smoke test." >&2
  exit 1
fi

hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$DMG" >/dev/null
APP="$MOUNT_POINT/Discord Voice Hotkey.app"

[[ -d "$APP" ]]
[[ -L "$MOUNT_POINT/Applications" ]]
[[ "$(readlink "$MOUNT_POINT/Applications")" == "/Applications" ]]
[[ -f "$APP/Contents/Resources/AppIcon.icns" ]]
codesign --verify --deep --strict --verbose=2 "$APP"
INSTALLED_APP="$INSTALL_ROOT/Applications/Discord Voice Hotkey.app"
mkdir -p "$(dirname "$INSTALLED_APP")"
ditto "$APP" "$INSTALLED_APP"
hdiutil detach "$MOUNT_POINT" -quiet

[[ -d "$INSTALLED_APP" ]]
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"
open "$INSTALLED_APP"

PID=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  PID="$(pgrep -x "$PROCESS_NAME" | sed -n '1p' || true)"
  [[ -n "$PID" ]] && break
  sleep 1
done

if [[ -z "$PID" ]]; then
  printf '%s\n' "The installed menu bar app did not remain running." >&2
  exit 1
fi

COMMAND="$(ps -p "$PID" -o command=)"
EXECUTABLE_DIR="$(cd "$INSTALLED_APP/Contents/MacOS" && pwd -P)"
EXPECTED_EXECUTABLE="$EXECUTABLE_DIR/$PROCESS_NAME"
if [[ "$COMMAND" != "$EXPECTED_EXECUTABLE"* ]]; then
  printf 'Observed PID %s belongs to unexpected command: %s\n' "$PID" "$COMMAND" >&2
  exit 1
fi

printf 'Installed DMG app launched successfully (PID %s).\n' "$PID"
