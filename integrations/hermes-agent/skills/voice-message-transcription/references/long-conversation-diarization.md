# Long Conversation Diarization (Local, Token-Free)

Use this when a long interview, counseling call, or meeting needs speaker-separated transcription and no Hugging Face token is available.

## Validated stack

- ASR: `faster-whisper`, preferably `large-v3` for difficult Mandarin/English code-switching.
- Segmentation: sherpa-onnx export of `pyannote/segmentation-3.0`.
- Embeddings: `3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx`.
- Clustering: sherpa-onnx `FastClusteringConfig`, with a known `num_clusters` when the user states the speaker count.

Model releases:

- Segmentation: `https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-segmentation-models`
- Embeddings: `https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-recongition-models` (upstream tag spelling is `recongition`)

## Audio preparation

1. Inspect duration/codec/channels with `ffprobe`.
2. Check whether stereo channels are actually distinct by decoding each channel and comparing hashes. Many meeting recordings are dual-mono.
3. Preserve the source. Make a 16 kHz, mono, PCM working WAV for diarization.
4. For ASR jobs that exceed foreground limits, split a working copy into roughly 590-second chunks and retain exact cumulative offsets.

## Diarization configuration

Known two-speaker example:

```python
config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
    segmentation=sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
        pyannote=sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(
            model=segmentation_model,
            window_shift_ratio=0.1,
        )
    ),
    embedding=sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=embedding_model),
    clustering=sherpa_onnx.FastClusteringConfig(num_clusters=2, threshold=0.5),
    min_duration_on=0.25,
    min_duration_off=0.30,
)
```

`window_shift_ratio=0.1` favors boundary detail but is CPU-intensive. Run it as a managed background task for long audio.

## Reconciliation workflow

1. Transcribe the complete audio or bounded chunks with `condition_on_previous_text=False`.
2. Restore chunk-local timestamps to the original timeline.
3. Assign each ASR segment to the diarization speaker with the greatest temporal overlap.
4. Map anonymous speaker IDs to names only from unmistakable turns near the start or from explicit self-identification.
5. Inspect every ASR segment that crosses a diarization boundary. It may contain words from both speakers.
6. Optionally generate speaker-masked tracks and re-transcribe them with VAD. Treat this as role-validation evidence only: hard masks can clip phonemes, fragment sentences, and reduce wording quality.
7. Use the coherent full-audio pass for primary wording, the diarization/masked pass for role assignment, and mark unresolved spans `[聽不清楚]`.

## Deliverables

For long user-facing conversations, produce both:

- a complete Markdown transcript with timestamps and role labels;
- an inline organized transcript or thematic rendering that preserves every substantive topic while removing filler.

State the model/diarization method in one sentence and disclose that overlapping speech may have uncertain role attribution.

## Verification checklist

- Source duration matches the final transcript timeline.
- Every expected chunk has non-empty JSON.
- Speaker-cluster durations/counts are plausible.
- Initial cluster-to-role mapping is manually checked.
- Amounts, dates, names, scripture quotations, and legal claims are not silently repaired from context.
- The complete artifact is readable and the inline version does not omit substantive sections.
