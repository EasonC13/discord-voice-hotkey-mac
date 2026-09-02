---
name: voice-message-transcription
description: Recover, inspect, transcribe, diarize, and quality-check voice messages, interviews, and long conversation recordings. Use when a chat attachment needs trustworthy transcription, role separation, or interpretation.
---

# Voice Message Transcription

## Goal

Produce a trustworthy transcript from a chat voice message. Recover the actual attachment first, inspect signal quality, run local speech recognition, and explicitly reject hallucinated text when the recording is too short, quiet, or speech-free.

## Workflow

1. **Recover the source attachment**
   - Treat “message has no text” and “message has no attachment” as different states.
   - Use any attachment path/URL supplied by the chat runtime first, even when the runtime labels a `voice-*.m4a` attachment as a **video** or caches it under `cache/documents/`. Verify the stream with `ffprobe`; an AAC-only stream is audio regardless of the chat label.
   - If the path is omitted, inspect recent files under `~/.hermes/audio_cache/` before asking the user to re-upload. Discord voice messages are commonly cached as `.ogg` Opus files.
   - Select by recent modification time and confirm that the file timestamp matches the user message; do not transcribe an older unrelated clip.
   - When the voice arrives during an active task, finish STT **before** deciding whether to continue, redirect, or interrupt. An immediate busy acknowledgement with an empty payload is not successful voice handling.

2. **Inspect before transcribing**
   - Run `ffprobe` to record duration, codec, sample rate, and channels.
   - Use `ffmpeg` `volumedetect` or `astats` when a first transcription is empty or suspicious.
   - Very short clips, fragmented speech, and low mean volume need stricter confidence handling.

3. **Run a local first pass**
   - Prefer `faster-whisper` through `uv` so the workflow works without a preinstalled Python package:
     `uv run --with faster-whisper python scripts/transcribe_voice.py AUDIO --model base`
   - Start with automatic language detection unless the user clearly states the language.
   - For a short or difficult clip, compare `base` and `small`, or rerun with the likely language explicitly set.
   - Never silently replace a user-validated authoritative model merely to reduce latency. If speed matters, preserve that model and use an explicitly provisional fast pass plus background authoritative verification. Equivalent results must stay silent; material differences produce one role-safe correction. See `references/dual-pass-stt-verification.md`.

4. **Use dual-pass latency optimization only with an authoritative verifier**
   - Do not silently replace an accuracy-tested model with a smaller one. If low latency matters, let a fast model produce a clearly provisional transcript while the tested model verifies in the background.
   - Treat the tested large-model transcript as authoritative. Equivalent punctuation/filler differences stay silent; material changes in negation, quantities, names, environments, requested actions, or safety facts trigger one correction.
   - A fast model can echo the configured `initial_prompt` as if it were speech, especially on short clips. Repetition of prompt phrases is a verification failure signal, not valid user content.
   - Preserve one verification job per audio event, update queued-event STT caches with the authoritative result, and inject at most one correction into an active turn. Never rewrite earlier conversation history.
   - Read-only work may begin from the provisional transcript. Before irreversible external actions, either wait for verification or fail closed when verification is discrepant, failed, or timed out.

5. **Handle long recordings deliberately**
   - For recordings long enough to exceed the foreground command limit, convert a working copy to 16 kHz mono and split it into roughly 8–10 minute chunks. Keep exact cumulative offsets so chunk timestamps can be restored to the original timeline.
   - Load the strongest justified model once when possible. If the reusable CLI reloads the model per chunk, run the bounded batch in a managed background process and verify every chunk produced non-empty JSON before aggregation.
   - Aggregate chunk JSON programmatically, restore global timestamps, and verify the combined duration/count instead of merging by eye.

6. **Separate speakers when requested**
   - Do not infer roles from text alone when acoustic diarization is feasible. For a known two-person conversation, run a two-cluster diarization pass and map anonymous clusters to roles from clear, early turns.
   - A tested local, token-free option is sherpa-onnx with the ONNX-exported pyannote segmentation model plus a Chinese-capable 3D-Speaker embedding model. See `references/long-conversation-diarization.md`.
   - Stereo does not imply separate speakers: compare decoded channel hashes first. Many meeting recordings contain identical left/right channels.
   - Assign ASR segments by maximum temporal overlap with diarization intervals, then inspect turn boundaries. Whisper segments may contain a short interjection from the other person; split or mark uncertain mixed turns rather than asserting the wrong role.
   - A speaker-masked re-transcription can validate role identity, but hard muting may clip words or create fragmented ASR. Use it as a cross-check, not automatically as the primary transcript.

7. **Normalize only when needed**
   - If the signal is quiet, create a temporary 16 kHz mono WAV with high/low-pass filtering and loudness normalization.
   - Keep the original file untouched.
   - Re-run recognition on the normalized copy and compare it with the original pass.

8. **Apply a confidence gate**
   - Do not report a phrase as a transcript merely because one model produced text.
   - Compare passes, detected-language probability, `avg_logprob`, and `no_speech_prob`.
   - Treat classic Whisper filler/hallucinations, conflicting languages, or high no-speech probability as unreliable.
   - If the evidence is weak, report `[音訊過短或聲音太弱，無法可靠辨識]` and explain the measurable reason (duration, low volume, or high no-speech probability).
   - Never convert a low-confidence guess such as “Thank you” into a definitive quote.

9. **Deliver useful output**
   - Provide the verbatim transcript first.
   - For EasonC13, the transcript must be the **first content in the reply**, before acknowledgements, summaries, plans, apologies, or tool results. This lets him verify exactly what was heard before judging the action taken.
   - Preserve wording faithfully while normalizing only obvious punctuation and Traditional Chinese orthography. Mark uncertain spans as `[聽不清楚]` or show bounded alternatives instead of silently repairing them.
   - Then provide a short meaning/intent summary and any requested response recommendation.
   - Match the user's language. For EasonC13, use Traditional Chinese and preserve English proper nouns.
   - For long conversations, deliver both: (a) a complete timestamped role transcript as a Markdown artifact and (b) an inline organized transcript or thematic rendering in the chat. The inline version may remove filler, but must not silently omit substantive claims.
   - State the diarization method and its limitation briefly. Keep anonymous labels until role mapping is supported by clear speech.
   - Do not “repair” uncertain theology, names, amounts, dates, legal facts, or quotations from expected context alone. Compare independent passes and mark `[聽不清楚]` when the audio does not resolve the phrase.

## Verification

Before answering, verify:

- the selected file is the newest relevant attachment;
- duration and codec are plausible;
- at least one transcription pass completed;
- low-confidence or conflicting outputs are labeled rather than asserted;
- temporary normalized files are not confused with the source;
- for chunked recordings, all chunks are present, offsets are restored, and the final timeline reaches the source duration;
- for diarized recordings, the requested/observed speaker count is plausible, cluster-to-role mapping is checked against clear turns, and mixed/overlapping speech is labeled cautiously;
- the full artifact exists and the inline organized version does not omit substantive sections.

## Pitfalls

- Do not immediately ask the user to resend when the attachment may already be in `~/.hermes/audio_cache/`.
- Do not assume an empty first Whisper result means the file is silent; inspect levels and retry once with normalization or a stronger model.
- Do not keep escalating models when audio analysis indicates mostly silence. Stop and report that the source is not intelligible.
- Do not persist environment-specific API-key failures as skill rules; local transcription is the stable fallback.
- Do not assume stereo channels represent different speakers; verify channel identity before building a split-channel workflow.
- Do not trust a single ASR segment's speaker label when the diarization shows a turn boundary inside it.
- Do not replace a coherent full-audio transcript with a more fragmented speaker-masked pass merely because the latter has cleaner role labels. Reconcile them: use the full pass for wording and the masked/diarized pass for role validation.
- Do not replace a validated authoritative STT model with a smaller model without explicit approval. Use a provisional/authoritative dual pass when low latency and validated accuracy are both required.
- During a multi-minute voice-pipeline implementation or benchmark, send a concise progress update before the long work stretch; silence is easily mistaken for another voice-handling failure.
- On long files, do not retry the same whole-file foreground command after a timeout. Move to bounded chunks or a managed background process and preserve intermediate JSON.

## References

- Chat-platform attachment recovery and confidence notes: `references/chat-voice-attachments.md`
- Dual-pass provisional/authoritative STT, semantic correction, side-effect gating, and tests: `references/dual-pass-stt-verification.md`
- Long-recording chunking, local diarization, and ASR/role reconciliation: `references/long-conversation-diarization.md`
- Reusable local transcriber: `scripts/transcribe_voice.py`
