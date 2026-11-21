import Foundation

/// A finalized AAC/M4A file borrowed for the duration of `transcribe`.
/// The adapter must honor cancellation and finish all access before returning.
public struct TranscriptionRequest: Sendable {
    public let audioURL: URL

    public init(audioURL: URL) { self.audioURL = audioURL }
}

public protocol TranscriptionProvider: Sendable {
    func transcribe(_ request: TranscriptionRequest) async throws -> String
}

public struct TranscriptTarget: Equatable {
    public let pid: Int32
    public let identity: UUID

    public init(pid: Int32, identity: UUID) {
        self.pid = pid
        self.identity = identity
    }
}

@MainActor
public protocol TranscriptDelivery: AnyObject {
    func captureTarget() -> TranscriptTarget?
    /// Requires unchanged focus, window, channel and composer; exact text; no attachments.
    func validate(_ target: TranscriptTarget, expectedText: String) -> Bool
    func paste(_ text: String, into target: TranscriptTarget, token: UUID) -> Bool
    /// Rechecks temporary clipboard ownership before posting Enter.
    func send(to target: TranscriptTarget, token: UUID, expectedText: String) -> Bool
    func release(_ target: TranscriptTarget)
    func deleteAudio(_ url: URL)
}

@MainActor
public final class TranscriptionFlow {
    public struct Recovery: Identifiable {
        public let id: UUID
        public let text: String
    }

    public enum Status {
        case unavailable, idle, transcribing, delivered, recoverable, failed
    }

    private let provider: (any TranscriptionProvider)?
    private let delivery: any TranscriptDelivery
    private let waitForPaste: @Sendable () async throws -> Void
    private var jobs: [UUID: Task<Void, Never>] = [:]
    private var latestRecording: UUID?
    private var shuttingDown = false
    public private(set) var recoveries: [Recovery] = []
    public private(set) var status: Status
    public var isAvailable: Bool { provider != nil && !shuttingDown }
    public var onChange: (() -> Void)?

    public init(provider: (any TranscriptionProvider)?, delivery: any TranscriptDelivery,
                waitForPaste: @escaping @Sendable () async throws -> Void = {
                    try await Task.sleep(for: .milliseconds(200))
                }) {
        self.provider = provider
        self.delivery = delivery
        self.waitForPaste = waitForPaste
        status = provider == nil ? .unavailable : .idle
    }

    // A successful microphone start in either mode revokes older auto-delivery authority.
    func recordingStarted(_ id: UUID) { latestRecording = id }

    func captureTarget() -> TranscriptTarget? { delivery.captureTarget() }

    func release(_ target: TranscriptTarget?) {
        if let target { delivery.release(target) }
    }

    func submit(_ url: URL, id: UUID, target: TranscriptTarget?) {
        guard let provider, !shuttingDown else {
            release(target)
            delivery.deleteAudio(url)
            return
        }
        let originalTarget = target.flatMap { delivery.validate($0, expectedText: "") ? $0 : nil }
        if originalTarget == nil { release(target) }
        status = .transcribing
        let request = TranscriptionRequest(audioURL: url)
        jobs[id] = Task { [self] in
            defer {
                release(originalTarget)
                jobs[id] = nil
                delivery.deleteAudio(url)
                onChange?()
            }
            do {
                let text = try await provider.transcribe(request).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !shuttingDown else { return }
                guard !text.isEmpty else { status = .failed; return }
                guard latestRecording == id, let originalTarget,
                      delivery.validate(originalTarget, expectedText: ""),
                      delivery.paste(text, into: originalTarget, token: id) else {
                    recover(text, id: id)
                    return
                }
                do { try await waitForPaste() } catch {
                    if !shuttingDown { recover(text, id: id) }
                    return
                }
                guard !shuttingDown else { return }
                guard latestRecording == id,
                      delivery.validate(originalTarget, expectedText: text),
                      delivery.send(to: originalTarget, token: id, expectedText: text) else {
                    recover(text, id: id)
                    return
                }
                status = .delivered
            } catch {
                // Provider errors can contain sensitive request or response details.
                if !shuttingDown { status = .failed }
            }
        }
        onChange?()
    }

    public var pendingCount: Int { jobs.count }

    public func discardRecovery(_ id: UUID) {
        recoveries.removeAll { $0.id == id }
        onChange?()
    }

    private func recover(_ text: String, id: UUID) {
        recoveries.append(Recovery(id: id, text: text))
        status = .recoverable
    }

    func shutdown() {
        shuttingDown = true
        for job in jobs.values { job.cancel() }
    }
}
