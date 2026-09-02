# Optimizing Hermes Agent voice control

Discord Voice Hotkey v2.3.1 sends mono Opus in an Ogg container. This avoids the `video/mp4` MIME ambiguity we observed with M4A and gives speech-to-text systems a compact, unambiguous audio stream.

This document records the maintainer's tested Hermes Agent workflow. The dual-pass gateway settings below describe an **experimental Hermes integration**, not a feature guaranteed by every upstream Hermes release.

## Why Ogg/Opus helps

The former M4A/AAC path could arrive from Discord as `video/mp4`, causing some Hermes gateways to preserve it as a video or generic document instead of running automatic STT. Discord can also rename a pasted Ogg recording to `audio_<content-hash>.ogg`, so a gateway integration should recognize both native voice notes and this narrow hashed-Ogg pattern.

The app now records through AVFoundation, converts with macOS's built-in `afconvert`, and locally wraps the Opus packets in a standards-compliant Ogg container. No FFmpeg, Homebrew package, network service, or cloud encoder is required.

## Accuracy-first latency optimization

A smaller Whisper model is faster, but it must not silently replace a model the user has already validated for accuracy. Our tested design is an optimistic dual pass:

1. `small` creates a **provisional** transcript so Hermes can begin reversible work quickly.
2. The previously validated `large-v3` model remains **authoritative** and runs in a tracked background verifier.
3. Equivalent punctuation, spacing, filler, or paraphrase differences remain silent.
4. Material changes in negation, quantities, names, environments, requested actions, paths, IDs, or safety facts produce exactly one correction.
5. Prior conversation history is never rewritten. A correction is append-only and session-scoped.

A real 4.93-second Ogg fixture on the maintainer host produced:

| Pass | Time | Result |
|---|---:|---|
| `small` provisional | 1.993 s | Correct Traditional Chinese meaning |
| `large-v3` authoritative | 7.134 s | Equivalent meaning |
| Verifier decision | — | `matched`; zero correction calls |

With an intentionally incorrect provisional transcript, the same real fixture produced `corrected` and exactly one active-turn correction.

### Important failure mode

On another short clip, the small model repeated the configured `initial_prompt` as if the user had spoken it. The authoritative model recovered the real request. Prompt repetition is therefore a verification-failure signal, not valid voice content. This is one reason `large-v3` remains authoritative.

## Example local configuration

The maintainer integration reads this optional configuration:

```yaml
stt:
  provider: local
  language: en                 # existing authoritative setup retained
  local:
    model: large-v3            # authoritative; never silently downgraded
    unload_after_idle_seconds: 0
    dual_pass:
      enabled: true
      fast_model: small
      fast_language: zh        # independent of the authoritative hint
      similarity_threshold: 0.72
```

On Hermes versions whose schema does not yet know `stt.local.dual_pass`, `hermes config set` may warn that the key is custom. Saving the key is not enough by itself: the gateway must contain a compatible dual-pass integration.

## Gateway integration invariants

A correct implementation should:

- centralize fresh, busy-steer, interrupt-monitor, and pending-drain voice handling on one event-level STT cache;
- schedule one authoritative pass per media snapshot;
- cancel or supersede stale verification after media merge, reset, or session-generation change;
- track verifier tasks in the gateway background-task set;
- keep equivalent verification completely silent;
- update queued-event caches with the authoritative transcript;
- inject at most one correction into the matching active turn, or queue one internal correction turn if the turn already ended;
- preserve strict message-role alternation and prompt-cache history;
- keep the provisional and authoritative model caches separate when model-reload latency matters.

## Side-effect safety

Starting from provisional text is safe for reading, searching, analysis, and drafting. If effect-capable tools may execute before verification finishes, add a just-in-time `pre_tool_call` gate:

- known read-only tools proceed immediately;
- effect-capable tools wait for the shared verification result;
- a match releases the call;
- discrepancy, failure, timeout, or stale ownership blocks it fail-closed;
- unknown, terminal, browser-interaction, file-write, messaging, and external-service tools default to effect-capable.

This is safer than relying only on approval prompts, which permissive modes may bypass.

## Included Hermes skill

The repository includes the maintainer's `voice-message-transcription` skill under:

```text
integrations/hermes-agent/skills/voice-message-transcription/
```

It documents attachment recovery, transcript-first replies, confidence gating, dual-pass verification, correction policy, and long-recording handling.

Copying the skill adds procedural guidance only. It does **not** patch an older Hermes gateway's runtime. Runtime changes should be reviewed and tested against the exact Hermes version in use.

## Verification checklist

The local Hermes integration was exercised with:

- 114 focused gateway/STT regression tests passing;
- real Ogg matched-path verification: no steer and no extra turn;
- real Ogg intentionally wrong-provisional path: one authoritative correction;
- Discord hashed Ogg recognition;
- explicit fast-pass language override;
- `large-v3` preserved as the authoritative configured model.

For production use, also test concurrent sessions, media-merge invalidation, stale generation after `/reset`, model-cache memory pressure, and side-effect gate behavior.
