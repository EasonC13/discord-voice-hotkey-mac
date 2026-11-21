import Foundation

public enum RecordingSessionError: LocalizedError, Equatable {
    case noUsableAudio
    case transcriptionUnavailable

    public var errorDescription: String? {
        switch self {
        case .noUsableAudio:
            return "No usable audio was recorded."
        case .transcriptionUnavailable:
            return "Transcription is not configured."
        }
    }
}

public struct RecordingContext: Equatable {
    public let clipboardToken: String
    public let frontmostApplicationPID: Int32?
    public let startedAt: Date

    public init(
        clipboardToken: String,
        frontmostApplicationPID: Int32?,
        startedAt: Date
    ) {
        self.clipboardToken = clipboardToken
        self.frontmostApplicationPID = frontmostApplicationPID
        self.startedAt = startedAt
    }
}

public protocol RecordingSessionRuntime: AnyObject {
    func captureContext(at date: Date) -> RecordingContext
    func startRecording() throws
    func stopRecording(cancel: Bool) -> URL?
    func stopTranscriptionRecording(cancel: Bool) -> URL?
    func activateApplication(pid: Int32?)
    func pasteAudioFile(_ url: URL) throws
    func deleteRecording(at url: URL)
    func shutdownRecordingStorage()
    func restoreClipboardNow(token: String)
    func restoreClipboardLater(token: String, completion: @escaping () -> Void)
}

public extension RecordingSessionRuntime {
    func stopTranscriptionRecording(cancel: Bool) -> URL? { stopRecording(cancel: cancel) }
}

public enum RecordingMode: Equatable { case audio, transcript }

@MainActor
public final class RecordingSessionMachine {
    private let runtime: RecordingSessionRuntime
    private let transcription: TranscriptionFlow?
    private var context: RecordingContext?
    private var transcriptTarget: TranscriptTarget?
    private var recordingID = UUID()
    public private(set) var recordingMode: RecordingMode?

    public var isRecording: Bool { context != nil }

    public init(runtime: RecordingSessionRuntime, transcription: TranscriptionFlow? = nil) {
        self.runtime = runtime
        self.transcription = transcription
    }

    public func shutdown() {
        transcription?.shutdown()
        transcription?.release(transcriptTarget)
        transcriptTarget = nil
        recordingMode = nil
        context = nil
        runtime.shutdownRecordingStorage()
    }

    public func toggle(mode: RecordingMode = .audio, now: Date = Date()) throws {
        // The other shortcut neither stops nor changes the active recording.
        if let recordingMode, recordingMode != mode { return }
        guard let activeContext = context else {
            if mode == .transcript, transcription?.isAvailable != true {
                throw RecordingSessionError.transcriptionUnavailable
            }
            let target = mode == .transcript ? transcription?.captureTarget() : nil
            let newContext = runtime.captureContext(at: now)
            do {
                try runtime.startRecording()
                context = newContext
                recordingMode = mode
                recordingID = UUID()
                transcription?.recordingStarted(recordingID)
                transcriptTarget = target
            } catch {
                transcription?.release(target)
                runtime.restoreClipboardNow(token: newContext.clipboardToken)
                throw error
            }
            return
        }

        context = nil
        recordingMode = nil
        let shouldCancel = now.timeIntervalSince(activeContext.startedAt) < 0.5
        if mode == .transcript {
            let target = transcriptTarget
            transcriptTarget = nil
            let outputURL = runtime.stopTranscriptionRecording(cancel: shouldCancel)
            runtime.restoreClipboardNow(token: activeContext.clipboardToken)
            if let outputURL {
                transcription?.submit(outputURL, id: recordingID, target: target)
            } else {
                transcription?.release(target)
                if !shouldCancel { throw RecordingSessionError.noUsableAudio }
            }
            return
        }
        let outputURL = runtime.stopRecording(cancel: shouldCancel)

        guard !shouldCancel else {
            runtime.restoreClipboardNow(token: activeContext.clipboardToken)
            return
        }

        guard let outputURL else {
            runtime.restoreClipboardNow(token: activeContext.clipboardToken)
            throw RecordingSessionError.noUsableAudio
        }

        runtime.activateApplication(pid: activeContext.frontmostApplicationPID)
        do {
            try runtime.pasteAudioFile(outputURL)
            runtime.restoreClipboardLater(token: activeContext.clipboardToken) {}
        } catch {
            runtime.deleteRecording(at: outputURL)
            runtime.restoreClipboardNow(token: activeContext.clipboardToken)
            throw error
        }
    }
}
