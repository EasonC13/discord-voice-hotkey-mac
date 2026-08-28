# Discord Voice Hotkey for macOS

[![Build macOS DMG](https://github.com/EasonC13/discord-voice-hotkey-mac/actions/workflows/build-dmg.yml/badge.svg)](https://github.com/EasonC13/discord-voice-hotkey-mac/actions/workflows/build-dmg.yml)

A native macOS menu bar app for recording and pasting audio attachments into Discord or any other app that accepts pasted files.

## Download

Download the latest DMG from [GitHub Releases](https://github.com/EasonC13/discord-voice-hotkey-mac/releases/latest).

## Install

1. Open `Discord-Voice-Hotkey-*.dmg`.
2. Drag **Discord Voice Hotkey.app** into the **Applications** shortcut.
3. Open the app from Applications.
   - Releases are ad-hoc signed but not Apple-notarized. On first launch, you may need to right-click the app and choose **Open**.
4. Allow **Microphone** and **Accessibility** access when macOS asks.

No Homebrew, Hammerspoon, FFmpeg, or background terminal process is required.

## Use

1. Keep the app running from the microphone icon in the macOS menu bar.
2. Put the cursor in a Discord message box.
3. Press `Control + Option + R` once to start recording.
4. Press it again to stop, paste the audio attachment, and send it automatically 0.2 seconds later.

Automatic sending is enabled by default. Turn **Send Automatically After Paste (0.2s)** off from the menu bar if you only want to stage the attachment. For safety, the app skips Enter if focus moved away from the original target app during the 0.2-second interval.

The app records native AAC audio in an `.m4a` container. Discord can play and upload this format directly.

### Custom shortcut

Open the menu bar icon and choose **Change Shortcut…**, then press any combination containing at least one modifier key. The shortcut is applied immediately and saved across app restarts.

### Clipboard behavior

The app snapshots the clipboard before recording. After pasting the audio file, it restores the previous clipboard approximately 1.5 seconds later. If you copy something new during that window, the newer clipboard is preserved instead of being overwritten.

Recordings shorter than 0.5 seconds are cancelled. Temporary recordings are removed after 30 minutes.

## Permissions

- **Microphone**: records audio through AVFoundation.
- **Accessibility**: sends `Command + V` to the app that was active when recording began.

The menu bar menu shows the current status of both permissions and links directly to the relevant System Settings pages.

## System requirements

- macOS 13 Ventura or newer
- Apple Silicon or Intel Mac supported by the GitHub macOS universal build environment

## Build locally

```bash
swift test
scripts/build-dmg.sh dev
scripts/smoke-test-app.sh
```

The build script:

- compiles the release Swift executable
- creates a real `.app` bundle
- performs ad-hoc code signing and strict signature verification
- builds and verifies the DMG with `hdiutil`
- generates a portable SHA-256 file

## Architecture

- **AppKit** menu bar application
- **Carbon** global hotkey registration
- **AVFoundation** native M4A/AAC recording
- **NSPasteboard** clipboard snapshot, file paste, and restoration
- **Core Graphics** synthetic `Command + V` after Accessibility authorization
- **Swift Package Manager** build and XCTest suite

## License

MIT
