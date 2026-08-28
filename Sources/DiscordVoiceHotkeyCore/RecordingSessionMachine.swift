import Foundation

public enum RecordingSessionError: LocalizedError, Equatable {
    case noUsableAudio
    case clipboardRestorationPending

    public var errorDescription: String? {
        switch self {
        case .noUsableAudio:
            return "No usable audio was recorded."
        case .clipboardRestorationPending:
            return "Please wait a moment for the clipboard to be restored."
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
    func activateApplication(pid: Int32?)
    func pasteAudioFile(_ url: URL) throws
    func deleteRecording(at url: URL)
    func shutdownRecordingStorage()
    func restoreClipboardNow(token: String)
    func restoreClipboardLater(token: String, completion: @escaping () -> Void)
}

public final class RecordingSessionMachine {
    private let runtime: RecordingSessionRuntime
    private var context: RecordingContext?
    private var isRestoringClipboard = false

    public var isRecording: Bool { context != nil }

    public init(runtime: RecordingSessionRuntime) {
        self.runtime = runtime
    }

    public func shutdown() {
        context = nil
        isRestoringClipboard = false
        runtime.shutdownRecordingStorage()
    }

    public func toggle(now: Date = Date()) throws {
        guard let activeContext = context else {
            if isRestoringClipboard {
                throw RecordingSessionError.clipboardRestorationPending
            }
            let newContext = runtime.captureContext(at: now)
            do {
                try runtime.startRecording()
                context = newContext
            } catch {
                runtime.restoreClipboardNow(token: newContext.clipboardToken)
                throw error
            }
            return
        }

        context = nil
        let shouldCancel = now.timeIntervalSince(activeContext.startedAt) < 0.5
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
            isRestoringClipboard = true
            runtime.restoreClipboardLater(token: activeContext.clipboardToken) { [weak self] in
                self?.isRestoringClipboard = false
            }
        } catch {
            runtime.deleteRecording(at: outputURL)
            runtime.restoreClipboardNow(token: activeContext.clipboardToken)
            throw error
        }
    }
}
