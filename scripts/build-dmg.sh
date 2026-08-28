#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' "DMG builds require macOS." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RAW_VERSION="${1:-dev}"
VERSION="${RAW_VERSION//\//-}"
DIST="$ROOT/dist"
STAGE="$DIST/dmg-root"
APP="$DIST/Discord Voice Hotkey.app"
DMG="$DIST/Discord-Voice-Hotkey-${VERSION}.dmg"

rm -rf "$STAGE" "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$STAGE"

swift build --package-path "$ROOT" -c release --product DiscordVoiceHotkey --arch arm64 --arch x86_64
BIN_DIR="$(swift build --package-path "$ROOT" -c release --show-bin-path --arch arm64 --arch x86_64)"
cp "$BIN_DIR/DiscordVoiceHotkey" "$APP/Contents/MacOS/DiscordVoiceHotkey"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/DiscordVoiceHotkey"
lipo "$APP/Contents/MacOS/DiscordVoiceHotkey" -verify_arch arm64 x86_64

plutil -lint "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

cp -R "$APP" "$STAGE/Discord Voice Hotkey.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG" "$DMG.sha256"
hdiutil create \
  -volname "Discord Voice Hotkey" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

hdiutil verify "$DMG"
"$ROOT/scripts/write-checksum.sh" "$DMG"
printf 'Built %s\n' "$DMG"
