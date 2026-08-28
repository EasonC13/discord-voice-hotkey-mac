#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' "DMG builds require macOS." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-dev}"
DIST="$ROOT/dist"
STAGE="$DIST/dmg-root"
DMG="$DIST/Discord-Voice-Hotkey-${VERSION}.dmg"

rm -rf "$STAGE"
mkdir -p "$STAGE/Discord Voice Hotkey/src"

cp "$ROOT/README.md" "$STAGE/Discord Voice Hotkey/README.md"
cp "$ROOT/LICENSE" "$STAGE/Discord Voice Hotkey/LICENSE"
cp "$ROOT/install.command" "$STAGE/Discord Voice Hotkey/Install Discord Voice Hotkey.command"
cp "$ROOT/src/recorder.lua" "$STAGE/Discord Voice Hotkey/src/recorder.lua"
cp "$ROOT/src/voice_hotkey.lua" "$STAGE/Discord Voice Hotkey/src/voice_hotkey.lua"
cp "$ROOT/src/record.sh" "$STAGE/Discord Voice Hotkey/src/record.sh"
chmod +x "$STAGE/Discord Voice Hotkey/Install Discord Voice Hotkey.command"
chmod +x "$STAGE/Discord Voice Hotkey/src/record.sh"

rm -f "$DMG"
hdiutil create \
  -volname "Discord Voice Hotkey" \
  -srcfolder "$STAGE/Discord Voice Hotkey" \
  -ov \
  -format UDZO \
  "$DMG"

hdiutil verify "$DMG"
shasum -a 256 "$DMG" > "$DMG.sha256"
printf 'Built %s\n' "$DMG"
