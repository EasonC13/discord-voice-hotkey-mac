# Hermes Agent integration assets

This directory packages the maintainer's reusable Hermes skill for trustworthy Discord voice-message transcription.

## Install the skill

Copy the skill directory into the active Hermes profile:

```bash
mkdir -p "$HERMES_HOME/skills/media"
cp -R integrations/hermes-agent/skills/voice-message-transcription \
  "$HERMES_HOME/skills/media/voice-message-transcription"
```

If `HERMES_HOME` is unset, the default profile normally uses `~/.hermes`.

The skill provides procedural guidance and reusable transcription scripts. It does not modify Hermes core runtime behavior. The optional dual-pass gateway workflow described in [`../../docs/hermes-agent-dual-pass-stt.md`](../../docs/hermes-agent-dual-pass-stt.md) requires a compatible Hermes version or separately reviewed runtime integration.
