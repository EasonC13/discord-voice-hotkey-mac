#!/usr/bin/env python3
"""Transcribe a voice attachment with faster-whisper and emit JSON.

Run through uv so dependencies need not be installed globally:
  uv run --with faster-whisper python scripts/transcribe_voice.py clip.ogg
"""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path


def normalize_audio(source: Path, target: Path) -> None:
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            str(source),
            "-af",
            "highpass=f=100,lowpass=f=8000,loudnorm=I=-16:LRA=7:TP=-1.5",
            "-ar",
            "16000",
            "-ac",
            "1",
            str(target),
        ],
        check=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("audio", type=Path)
    parser.add_argument("--model", default="base")
    parser.add_argument("--language", default=None)
    parser.add_argument("--normalize", action="store_true")
    parser.add_argument("--beam-size", type=int, default=5)
    args = parser.parse_args()

    if not args.audio.is_file():
        raise SystemExit(f"Audio file not found: {args.audio}")

    from faster_whisper import WhisperModel

    temp_dir = None
    source = args.audio
    try:
        if args.normalize:
            temp_dir = tempfile.TemporaryDirectory(prefix="voice-transcribe-")
            source = Path(temp_dir.name) / "normalized.wav"
            normalize_audio(args.audio, source)

        model = WhisperModel(args.model, device="cpu", compute_type="int8")
        segments, info = model.transcribe(
            str(source),
            language=args.language,
            beam_size=args.beam_size,
            best_of=args.beam_size,
            temperature=0.0,
            condition_on_previous_text=False,
        )
        rows = []
        for segment in segments:
            rows.append(
                {
                    "start": round(segment.start, 3),
                    "end": round(segment.end, 3),
                    "text": segment.text.strip(),
                    "avg_logprob": round(segment.avg_logprob, 4),
                    "no_speech_prob": round(segment.no_speech_prob, 4),
                }
            )
        print(
            json.dumps(
                {
                    "source": str(args.audio),
                    "normalized": args.normalize,
                    "model": args.model,
                    "requested_language": args.language,
                    "detected_language": info.language,
                    "language_probability": round(info.language_probability, 4),
                    "duration": round(info.duration, 3),
                    "segments": rows,
                    "text": " ".join(r["text"] for r in rows).strip(),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
    finally:
        if temp_dir is not None:
            temp_dir.cleanup()


if __name__ == "__main__":
    main()
