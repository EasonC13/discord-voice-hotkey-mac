import Foundation
import XCTest
@testable import DiscordVoiceHotkeyCore

final class RecordingSessionMachineTests: XCTestCase {
    func testFirstToggleCapturesContextAndStartsRecording() throws {
        let runtime = MockRuntime()
        let machine = RecordingSessionMachine(runtime: runtime)
        let now = Date(timeIntervalSince1970: 100)

        try machine.toggle(now: now)

        XCTAssertTrue(machine.isRecording)
        XCTAssertEqual(runtime.events, ["capture", "start"])
    }

    func testSecondTogglePastesFinishedAudioAndSchedulesClipboardRestore() throws {
        let runtime = MockRuntime()
        let machine = RecordingSessionMachine(runtime: runtime)
        let started = Date(timeIntervalSince1970: 100)

        try machine.toggle(now: started)
        try machine.toggle(now: started.addingTimeInterval(2))

        XCTAssertFalse(machine.isRecording)
        XCTAssertEqual(runtime.events, [
            "capture",
            "start",
            "stop:false",
            "activate:42",
            "paste:voice.m4a",
            "restoreLater:clipboard-1",
        ])
    }

    func testRecordingShorterThanHalfSecondCancelsWithoutPasting() throws {
        let runtime = MockRuntime()
        let machine = RecordingSessionMachine(runtime: runtime)
        let started = Date(timeIntervalSince1970: 100)

        try machine.toggle(now: started)
        try machine.toggle(now: started.addingTimeInterval(0.2))

        XCTAssertFalse(machine.isRecording)
        XCTAssertEqual(runtime.events, [
            "capture",
            "start",
            "stop:true",
            "restoreNow:clipboard-1",
        ])
    }

    func testMissingOutputThrowsAndRestoresClipboardWithoutPasting() throws {
        let runtime = MockRuntime()
        runtime.outputURL = nil
        let machine = RecordingSessionMachine(runtime: runtime)
        let started = Date(timeIntervalSince1970: 100)

        try machine.toggle(now: started)
        XCTAssertThrowsError(try machine.toggle(now: started.addingTimeInterval(2))) { error in
            XCTAssertEqual(error as? RecordingSessionError, .noUsableAudio)
        }

        XCTAssertFalse(machine.isRecording)
        XCTAssertEqual(runtime.events, [
            "capture",
            "start",
            "stop:false",
            "restoreNow:clipboard-1",
        ])
    }

    func testNewRecordingIsBlockedUntilClipboardRestorationCompletes() throws {
        let runtime = MockRuntime()
        let machine = RecordingSessionMachine(runtime: runtime)
        let started = Date(timeIntervalSince1970: 100)

        try machine.toggle(now: started)
        try machine.toggle(now: started.addingTimeInterval(2))
        let eventsAfterPaste = runtime.events

        XCTAssertThrowsError(try machine.toggle(now: started.addingTimeInterval(4))) { error in
            XCTAssertEqual(error as? RecordingSessionError, .clipboardRestorationPending)
        }
        XCTAssertEqual(runtime.events, eventsAfterPaste)

        runtime.completeRestore()
        try machine.toggle(now: started.addingTimeInterval(4))
        XCTAssertTrue(machine.isRecording)
        XCTAssertEqual(Array(runtime.events.suffix(2)), ["capture", "start"])
    }

    func testPasteFailureDeletesOutputBeforeRestoringClipboard() throws {
        let runtime = MockRuntime()
        runtime.pasteError = MockFailure.paste
        let machine = RecordingSessionMachine(runtime: runtime)
        let started = Date(timeIntervalSince1970: 100)

        try machine.toggle(now: started)
        XCTAssertThrowsError(try machine.toggle(now: started.addingTimeInterval(2)))

        XCTAssertEqual(runtime.events, [
            "capture",
            "start",
            "stop:false",
            "activate:42",
            "paste:voice.m4a",
            "delete:voice.m4a",
            "restoreNow:clipboard-1",
        ])
    }

    func testShutdownClearsActiveAndCachedRecordings() throws {
        let runtime = MockRuntime()
        let machine = RecordingSessionMachine(runtime: runtime)

        try machine.toggle(now: Date(timeIntervalSince1970: 100))
        machine.shutdown()

        XCTAssertFalse(machine.isRecording)
        XCTAssertEqual(runtime.events, ["capture", "start", "shutdown"])
    }
}

private enum MockFailure: Error {
    case paste
}

private final class MockRuntime: RecordingSessionRuntime {
    var events: [String] = []
    var outputURL: URL? = URL(fileURLWithPath: "/tmp/voice.m4a")
    var pasteError: Error?
    var restoreCompletion: (() -> Void)?

    func captureContext(at date: Date) -> RecordingContext {
        events.append("capture")
        return RecordingContext(
            clipboardToken: "clipboard-1",
            frontmostApplicationPID: 42,
            startedAt: date
        )
    }

    func startRecording() throws {
        events.append("start")
    }

    func stopRecording(cancel: Bool) -> URL? {
        events.append("stop:\(cancel)")
        return cancel ? nil : outputURL
    }

    func activateApplication(pid: Int32?) {
        events.append("activate:\(pid.map(String.init) ?? "nil")")
    }

    func pasteAudioFile(_ url: URL) throws {
        events.append("paste:\(url.lastPathComponent)")
        if let pasteError { throw pasteError }
    }

    func deleteRecording(at url: URL) {
        events.append("delete:\(url.lastPathComponent)")
    }

    func shutdownRecordingStorage() {
        events.append("shutdown")
    }

    func restoreClipboardNow(token: String) {
        events.append("restoreNow:\(token)")
    }

    func restoreClipboardLater(token: String) {
        events.append("restoreLater:\(token)")
    }

    func restoreClipboardLater(token: String, completion: @escaping () -> Void) {
        events.append("restoreLater:\(token)")
        restoreCompletion = completion
    }

    func completeRestore() {
        let completion = restoreCompletion
        restoreCompletion = nil
        completion?()
    }
}
