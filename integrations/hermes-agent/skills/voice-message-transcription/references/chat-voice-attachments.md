# Chat voice attachments: recovery and confidence notes

## Discord/Hermes attachment pattern

A Discord Voice Message may reach the conversation as an attachment with no text and no visible path in the rendered transcript. Before declaring it unavailable, inspect recent files in:

```text
~/.hermes/audio_cache/
```

Native Discord voice notes commonly use `.ogg` with Opus audio, 48 kHz mono, and may include `ENCODER=Discord Client` metadata. Voice-recorder/share-sheet uploads may instead arrive as ordinary audio attachments named `voice-<timestamp>.m4a`; stock routing can classify those as `AUDIO` rather than `VOICE`, so a media-only busy-run interrupt may contain no transcript unless the adapter recognizes the filename or the clip is transcribed manually. Select the newest matching file and verify its modification time against the message.

## Inspection commands

```bash
ffprobe -v error \
  -show_entries format=duration,size \
  -show_entries stream=codec_name,sample_rate,channels \
  -of json voice.ogg

ffmpeg -hide_banner -i voice.ogg -af volumedetect -f null -
ffmpeg -hide_banner -i voice.ogg -af silencedetect=noise=-45dB:d=0.2 -f null -
```

A first pass can be run without installing packages globally:

```bash
uv run --with faster-whisper \
  python scripts/transcribe_voice.py voice.ogg --model base
```

For a weak signal:

```bash
uv run --with faster-whisper \
  python scripts/transcribe_voice.py voice.ogg --model small --normalize
```

## Confidence lesson

Short weak clips can produce mutually incompatible results:

- a smaller model may return no segments;
- a stronger model may guess a common phrase in the wrong language;
- forcing a language can produce a familiar Whisper hallucination;
- `no_speech_prob` can remain high despite generated text.

Use agreement across passes and signal measurements, not model size alone. If one pass guesses a phrase while another is empty and no-speech probability is high, report the clip as unintelligible instead of quoting the guess.

## User-facing response pattern

State that the attachment was successfully recovered, then distinguish technical success from transcription quality:

> 已取得並讀取語音附件，但錄音過短或聲音太弱，無法產生可靠逐字稿。

Include duration or confidence evidence when useful, and ask for a clearer 5–10 second re-recording only after local recovery and one quality-controlled retry have failed.
