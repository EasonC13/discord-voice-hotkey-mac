import Foundation
import XCTest
@testable import DiscordVoiceHotkeyCore

final class TimedProcessRunnerTests: XCTestCase {
    func testTimeoutTerminatesChildWithoutBlockingCaller() throws {
        let runner = TimedProcessRunner(timeout: 0.05, terminationGrace: 0.2)
        let started = Date()

        XCTAssertThrowsError(
            try runner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"]
            )
        ) { error in
            guard case TimedProcessRunnerError.timedOut = error else {
                return XCTFail("Expected timedOut, got \(error)")
            }
        }

        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }

    func testNonzeroExitIncludesStderrWithoutShellInvocation() throws {
        let runner = TimedProcessRunner(timeout: 1, terminationGrace: 0.2)

        XCTAssertThrowsError(
            try runner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf conversion-failed >&2; exit 7"]
            )
        ) { error in
            guard case let TimedProcessRunnerError.nonzeroExit(status, stderr) = error else {
                return XCTFail("Expected nonzeroExit, got \(error)")
            }
            XCTAssertEqual(status, 7)
            XCTAssertEqual(stderr, "conversion-failed")
        }
    }
}
