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

    func testMissingOutputRestoresClipboardWithoutPasting() throws {
        let runtime = MockRuntime()
        runtime.outputURL = nil
        let machine = RecordingSessionMachine(runtime: runtime)
        let started = Date(timeIntervalSince1970: 100)

        try machine.toggle(now: started)
        try machine.toggle(now: started.addingTimeInterval(2))

        XCTAssertFalse(machine.isRecording)
        XCTAssertEqual(runtime.events, [
            "capture",
            "start",
            "stop:false",
            "restoreNow:clipboard-1",
        ])
    }
}

private final class MockRuntime: RecordingSessionRuntime {
    var events: [String] = []
    var outputURL: URL? = URL(fileURLWithPath: "/tmp/voice.m4a")

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
    }

    func restoreClipboardNow(token: String) {
        events.append("restoreNow:\(token)")
    }

    func restoreClipboardLater(token: String) {
        events.append("restoreLater:\(token)")
    }
}
