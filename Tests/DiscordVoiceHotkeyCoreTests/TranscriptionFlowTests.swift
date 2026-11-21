import Foundation
import XCTest
@testable import DiscordVoiceHotkeyCore

@MainActor
final class TranscriptionFlowTests: XCTestCase {
    func testNetworkDoesNotOwnMicrophoneAndOutOfOrderResultsDoNotPasteOverNewerRecording() async throws {
        let provider = HeldProvider()
        let runtime = TranscriptRuntime()
        let flow = TranscriptionFlow(provider: provider, delivery: runtime)
        let recorder = SharedRecorder()
        let machine = RecordingSessionMachine(runtime: recorder, transcription: flow)
        let start = Date(timeIntervalSince1970: 100)
        try machine.toggle(mode: .transcript, now: start)
        try machine.toggle(mode: .audio, now: start.addingTimeInterval(1))
        XCTAssertEqual(machine.recordingMode, .transcript)
        try machine.toggle(mode: .transcript, now: start.addingTimeInterval(2))
        let first = await provider.next()
        XCTAssertNil(machine.recordingMode)
        try machine.toggle(mode: .transcript, now: start.addingTimeInterval(3))
        try machine.toggle(mode: .transcript, now: start.addingTimeInterval(4))
        let second = await provider.next()
        second.finish(.success("newer"))
        await runtime.nextDeletion()
        first.finish(.success("older"))
        await runtime.nextDeletion()
        XCTAssertEqual(runtime.pastes, ["newer"])
        XCTAssertEqual(flow.recoveries.map(\.text), ["older"])
        XCTAssertEqual(recorder.audioPastes, 0)
        XCTAssertEqual(runtime.deleted, [second.request.audioURL, first.request.audioURL])
    }

    func testPasteWaitFailureRecoversAlreadyReturnedText() async throws {
        let provider = HeldProvider()
        let runtime = TranscriptRuntime()
        let flow = TranscriptionFlow(provider: provider, delivery: runtime, waitForPaste: { throw CancellationError() })
        let machine = RecordingSessionMachine(runtime: SharedRecorder(), transcription: flow)
        let start = Date(timeIntervalSince1970: 100)
        try machine.toggle(mode: .transcript, now: start)
        try machine.toggle(mode: .transcript, now: start.addingTimeInterval(2))
        let call = await provider.next()
        call.finish(.success("recover me"))
        await runtime.nextDeletion()
        XCTAssertEqual(flow.recoveries.map(\.text), ["recover me"])
    }
}

private actor HeldProvider: TranscriptionProvider {
    struct Pending: Sendable {
        let request: TranscriptionRequest
        let finish: @Sendable (Result<String, Error>) -> Void
    }
    private var pending: [Pending] = []
    private var waiter: CheckedContinuation<Pending, Never>?

    func transcribe(_ request: TranscriptionRequest) async throws -> String {
        try await withCheckedThrowingContinuation { response in
            let call = Pending(request: request, finish: { response.resume(with: $0) })
            if let waiter {
                self.waiter = nil
                waiter.resume(returning: call)
            } else {
                pending.append(call)
            }
        }
    }

    func next() async -> Pending {
        if !pending.isEmpty { return pending.removeFirst() }
        return await withCheckedContinuation { waiter = $0 }
    }
}

@MainActor
private final class TranscriptRuntime: TranscriptDelivery {
    var pastes: [String] = []
    var deleted: [URL] = []
    private var deletions = 0
    private var waiter: CheckedContinuation<Void, Never>?

    func captureTarget() -> TranscriptTarget? { TranscriptTarget(pid: 42, identity: UUID()) }
    func validate(_ target: TranscriptTarget, expectedText: String) -> Bool { true }
    func paste(_ text: String, into target: TranscriptTarget, token: UUID) -> Bool {
        pastes.append(text)
        return true
    }
    func send(to target: TranscriptTarget, token: UUID, expectedText: String) -> Bool { true }
    func release(_ target: TranscriptTarget) {}
    func deleteAudio(_ url: URL) {
        deleted.append(url)
        if let waiter {
            self.waiter = nil
            waiter.resume()
        } else { deletions += 1 }
    }
    func nextDeletion() async {
        if deletions > 0 { deletions -= 1; return }
        await withCheckedContinuation { waiter = $0 }
    }
}

private final class SharedRecorder: RecordingSessionRuntime {
    var audioPastes = 0
    func captureContext(at date: Date) -> RecordingContext {
        RecordingContext(clipboardToken: UUID().uuidString, frontmostApplicationPID: 42, startedAt: date)
    }
    func startRecording() throws {}
    func stopRecording(cancel: Bool) -> URL? { cancel ? nil : URL(fileURLWithPath: "/synthetic/\(UUID()).m4a") }
    func activateApplication(pid: Int32?) {}
    func pasteAudioFile(_ url: URL) throws { audioPastes += 1 }
    func deleteRecording(at url: URL) {}
    func shutdownRecordingStorage() {}
    func restoreClipboardNow(token: String) {}
    func restoreClipboardLater(token: String, completion: @escaping () -> Void) {}
}
