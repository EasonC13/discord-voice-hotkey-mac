#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' "This installer must be run on macOS." >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  printf '%s\n' "Homebrew is required: https://brew.sh" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  printf '%s\n' "Installing ffmpeg…"
  brew install ffmpeg
fi

if [[ ! -d "/Applications/Hammerspoon.app" && ! -d "$HOME/Applications/Hammerspoon.app" ]]; then
  printf '%s\n' "Installing Hammerspoon…"
  brew install --cask hammerspoon
fi

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)/src"
TARGET_DIR="$HOME/.hammerspoon/discord-voice-hotkey"
INIT_FILE="$HOME/.hammerspoon/init.lua"
MARKER="Discord Voice Hotkey (managed block)"

mkdir -p "$TARGET_DIR"
cp "$SOURCE_DIR/recorder.lua" "$TARGET_DIR/recorder.lua"
cp "$SOURCE_DIR/voice_hotkey.lua" "$TARGET_DIR/voice_hotkey.lua"
cp "$SOURCE_DIR/record.sh" "$TARGET_DIR/record.sh"
chmod +x "$TARGET_DIR/record.sh"

mkdir -p "$(dirname "$INIT_FILE")"
if [[ -f "$INIT_FILE" ]]; then
  BACKUP="$INIT_FILE.backup.$(date +%Y%m%d-%H%M%S)"
  cp "$INIT_FILE" "$BACKUP"
  printf 'Existing Hammerspoon config backed up to: %s\n' "$BACKUP"
else
  : > "$INIT_FILE"
fi

if ! grep -Fq "$MARKER" "$INIT_FILE"; then
  {
    printf '\n-- BEGIN %s\n' "$MARKER"
    printf 'DiscordVoiceHotkey = dofile(hs.configdir .. "/discord-voice-hotkey/voice_hotkey.lua")\n'
    printf '%s\n' "-- END $MARKER"
  } >> "$INIT_FILE"
fi

open -a Hammerspoon

cat <<'MESSAGE'

Installed Discord Voice Hotkey.

One-time macOS permissions:
1. System Settings → Privacy & Security → Accessibility → enable Hammerspoon.
2. Press Control+Option+R once and allow microphone access when prompted.
3. From the Hammerspoon menu bar icon, choose Reload Config if needed.

Usage in Discord:
- Control+Option+R starts recording.
- Press it again to stop and paste the MP3 attachment.
- Your prior clipboard is restored after the paste.
- Enter/Return is never pressed automatically.
MESSAGE
