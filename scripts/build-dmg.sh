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
ICONSET="$DIST/AppIcon.iconset"

rm -rf "$STAGE" "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$STAGE"

swift build --package-path "$ROOT" -c release --product DiscordVoiceHotkey --arch arm64 --arch x86_64
BIN_DIR="$(swift build --package-path "$ROOT" -c release --show-bin-path --arch arm64 --arch x86_64)"
cp "$BIN_DIR/DiscordVoiceHotkey" "$APP/Contents/MacOS/DiscordVoiceHotkey"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/DiscordVoiceHotkey"
lipo "$APP/Contents/MacOS/DiscordVoiceHotkey" -verify_arch arm64 x86_64

mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT/Resources/AppIcon-1024.png" \
    --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$ROOT/Resources/AppIcon-1024.png" \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

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
