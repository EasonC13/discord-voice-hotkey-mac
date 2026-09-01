# Discord Voice Hotkey for macOS

**English** | [繁體中文](README.zh-TW.md)

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
3. Press `Control + R` once to start recording.
4. Press it again to stop, paste the audio attachment, and send it automatically 0.2 seconds later.

Automatic sending is enabled by default. Turn **Send Automatically After Paste (0.2s)** off from the menu bar if you only want to stage the attachment. For safety, the app skips Enter if focus moved away from the original target app during the 0.2-second interval.

The app records native AAC audio in an `.m4a` container. Discord can play and upload this format directly.

### Custom shortcut

Open the menu bar icon and choose **Change Shortcut…**, then press any combination containing at least one modifier key. The shortcut is applied immediately and saved across app restarts. Updating the app does not overwrite a shortcut you previously customized.

### Clipboard behavior

The app snapshots the clipboard before recording. After pasting the audio file, it restores the previous clipboard approximately 1.5 seconds later. If you copy something new during that window, the newer clipboard is preserved instead of being overwritten.

Recordings shorter than 0.5 seconds are cancelled. Temporary recordings are removed after 30 minutes.

## Using it with Hermes Agent

This app records and sends the audio file. [Hermes Agent](https://github.com/NousResearch/hermes-agent) can then automatically transcribe Discord voice attachments and treat the transcript as a normal message.

### Recommended speech-to-text engine

We recommend **local faster-whisper** first. Audio stays on the machine running Hermes, no API key or cloud transcription service is required, and it is the setup used by this project's maintainers. Our current deployment uses the `large-v3` model for strong Traditional Chinese, English, and mixed-language accuracy:

```bash
hermes config set stt.enabled true
hermes config set stt.provider local
hermes config set stt.local.model large-v3
```

The model runs on the Hermes host, which can be your Mac or a separate server. If `large-v3` is too slow or memory-intensive on your hardware, try `medium`, `small`, or `base` in that order.

**Groq Whisper API** is an optional cloud fallback when the Hermes host cannot run a local model or minimum latency matters more than local processing. Add your `GROQ_API_KEY` through Hermes setup, then select Groq:

```bash
hermes config set stt.enabled true
hermes config set stt.provider groq
```

Use `hermes tools` to install or configure voice dependencies and credentials. See the official [Hermes Voice & TTS documentation](https://hermes-agent.nousresearch.com/docs/user-guide/features/tts) for all supported engines, including OpenAI, Mistral, xAI, ElevenLabs, and DeepInfra.

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
