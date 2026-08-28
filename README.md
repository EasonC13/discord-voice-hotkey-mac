# Discord Voice Hotkey for macOS

[![Build macOS DMG](https://github.com/EasonC13/discord-voice-hotkey-mac/actions/workflows/build-dmg.yml/badge.svg)](https://github.com/EasonC13/discord-voice-hotkey-mac/actions/workflows/build-dmg.yml)

Press one global shortcut to start recording and press it again to paste an MP3 into Discord. Your previous clipboard contents are restored automatically.

## Download

Download the latest DMG from [GitHub Releases](https://github.com/EasonC13/discord-voice-hotkey-mac/releases/latest).

## Install from the DMG

1. Open `Discord-Voice-Hotkey-*.dmg`.
2. Open **Install Discord Voice Hotkey.command**.
   - The release is open source but not Apple-notarized. If macOS blocks it, right-click it and choose **Open**.
3. Grant Hammerspoon **Accessibility** permission.
4. Press `Control + Option + R` once and grant microphone permission.
5. If necessary, click the Hammerspoon menu-bar icon and choose **Reload Config**.

The installer uses Homebrew to install `ffmpeg` and Hammerspoon if they are missing. It backs up an existing `~/.hammerspoon/init.lua` before appending one clearly marked loader block.

## Use

1. Put the cursor in a Discord message box.
2. Press `Control + Option + R` to start recording.
3. Press it again to stop.
4. The MP3 is pasted as an attachment, but **not sent**.
5. The clipboard contents from before recording are restored approximately 1.5 seconds later.

If you copy something new during that 1.5-second window, the tool preserves the newer clipboard instead of overwriting it.

Recordings shorter than 0.5 seconds are cancelled. Temporary MP3 files are removed after 30 minutes.

## Permissions

- **Accessibility**: required to issue `Command + V` in Discord.
- **Microphone**: required to record through FFmpeg/AVFoundation.

Settings location: **System Settings → Privacy & Security**.

## Change the shortcut

Edit `~/.hammerspoon/discord-voice-hotkey/voice_hotkey.lua` and find:

```lua
hs.hotkey.bind({ "ctrl", "alt" }, "R", function()
```

Then reload the Hammerspoon configuration.

## Build locally

DMG creation requires macOS:

```bash
npm ci
npm test
npm run check:lua
scripts/build-dmg.sh dev
```

The verified DMG and SHA-256 file are written to `dist/`.

## Uninstall

1. Remove the managed block between `BEGIN Discord Voice Hotkey` and `END Discord Voice Hotkey` from `~/.hammerspoon/init.lua`.
2. Delete `~/.hammerspoon/discord-voice-hotkey`.
3. Reload Hammerspoon.

Hammerspoon and FFmpeg are left installed because other applications may use them.

## License

MIT
