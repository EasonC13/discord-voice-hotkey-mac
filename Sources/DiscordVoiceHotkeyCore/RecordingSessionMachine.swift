import Foundation

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
    func restoreClipboardNow(token: String)
    func restoreClipboardLater(token: String)
}

public final class RecordingSessionMachine {
    private let runtime: RecordingSessionRuntime
    private var context: RecordingContext?

    public var isRecording: Bool { context != nil }

    public init(runtime: RecordingSessionRuntime) {
        self.runtime = runtime
    }

    public func toggle(now: Date = Date()) throws {
        guard let activeContext = context else {
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

        guard !shouldCancel, let outputURL else {
            runtime.restoreClipboardNow(token: activeContext.clipboardToken)
            return
        }

        runtime.activateApplication(pid: activeContext.frontmostApplicationPID)
        do {
            try runtime.pasteAudioFile(outputURL)
            runtime.restoreClipboardLater(token: activeContext.clipboardToken)
        } catch {
            runtime.restoreClipboardNow(token: activeContext.clipboardToken)
            throw error
        }
    }
}
