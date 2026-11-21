# Standalone transcription integration (draft)

This branch intentionally has no production provider and must not be tagged. Ctrl+R (or the saved audio shortcut) still records audio. Ctrl+1 is reserved for transcription only when it does not conflict with the saved audio shortcut. A held chord fires once; the other mode's chord does not stop an active recording. With no provider configured, Ctrl+1 does not start the microphone.

## Provider seam

Implement `TranscriptionProvider.transcribe(_:)` and inject it in `AppDelegate`'s `TranscriptionFlow` initializer only after the standalone auth route is agreed. The input is a borrowed, finalized AAC/M4A file URL, with no prompt, Discord metadata, or credentials in the request model. The adapter owns provider selection/authentication, bounded transport and cancellation, and returns only the transcript; it must finish accessing the file before returning. Use app-specific authorization only. Do not read, export, or fall back to managed Hermes credentials. Test external behavior with a mocked transport and synthetic audio. Do not log keys, transcripts, or raw provider errors.

The microphone is free as soon as recording stops. Both modes share one recorder and one clipboard ownership transaction. Only the most recently started successful recording can authorize automatic transcript delivery. Older completions go to the in-memory recovery menu; they do not write the clipboard. Explicit Copy is a normal user clipboard write. Recovered transcripts are not persisted and are lost when the app quits.

## Native send gate

`MacTranscriptDelivery` requires the original foreground Discord process and launch date, the same AX window, focused composer and web area, and an authoritative channel URL. It must see an exactly empty composer before posting Command-V and exactly the pasted transcript before posting Enter. Enter also requires the same clipboard write owner. It never activates a Discord window. If validation fails after paste, it does not clear or send the draft; the transcript remains recoverable. A different app or Discord client/layout not exposing these attributes is unsupported and goes to recovery.

A second, independent integration gate is `MacTranscriptDelivery.ComposerProof`: wire a supported Discord AX implementation only after verifying that it can positively identify the message composer, verify no staged attachments, and invalidate its revision on focus/window/channel/attachment interruption, including an away-and-back change. It must return `nil` on unknown state, lost observation or unsupported AX layout. PID, window title, empty text, and absence of exposed attachment nodes are not proof. No proof implementation is enabled on this branch, so even a provider-injected build recovers transcripts rather than automatically pasting/sending. Do not replace this gate with an always-true closure. AX reads and keyboard delivery are not atomic across processes; native acceptance must cover Discord's event ordering as well as ordinary focus, channel and attachment changes.

## Acceptance before release

The existing macOS workflow runs the Swift suite, builds and verifies the ad-hoc signed universal DMG, and smoke-launches the packaged app. Draft CI artifacts are not releases. Native CI does not test real Discord or the physical microphone. Verify the supported Discord layout (including drafts, attachments, app/window/channel changes, and clipboard changes), a synthetic provider fixture, and the exact post-merge main and tagged artifact before publishing. No test should post to Discord or upload a user's recording.
