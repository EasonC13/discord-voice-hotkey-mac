import XCTest
@testable import DiscordVoiceHotkeyCore

final class ClipboardTransactionTests: XCTestCase {
    func testThreePasteBurstWithEveryCallbackOrderRestoresExactlyOnce() {
        let orders = [["a", "b", "c"], ["a", "c", "b"], ["b", "a", "c"],
                      ["b", "c", "a"], ["c", "a", "b"], ["c", "b", "a"]]
        for order in orders {
            var clipboard = ClipboardTransaction<String>()
            clipboard.preparePaste(snapshot: "original", changeCount: 1)
            clipboard.didWrite(token: "a", changeCount: 2)
            clipboard.preparePaste(snapshot: "audio-a", changeCount: 2)
            clipboard.didWrite(token: "b", changeCount: 3)
            clipboard.preparePaste(snapshot: "audio-b", changeCount: 3)
            clipboard.didWrite(token: "c", changeCount: 4)
            var count = 4
            var restored: [String] = []
            for token in order {
                if let snapshot = clipboard.restore(token: token, changeCount: count) {
                    restored.append(snapshot)
                    count += 1
                }
            }
            XCTAssertEqual(restored, ["original"], "callback order: \(order)")
            XCTAssertNil(clipboard.ownerToken)
        }
    }

    func testOverlappingPastesRestoreOriginalNotTemporaryAudio() {
        var clipboard = ClipboardTransaction<String>()
        clipboard.preparePaste(snapshot: "original", changeCount: 1)
        clipboard.didWrite(token: "a", changeCount: 2)
        clipboard.preparePaste(snapshot: "audio-a", changeCount: 2)
        clipboard.didWrite(token: "b", changeCount: 3)
        XCTAssertNil(clipboard.restore(token: "a", changeCount: 3))
        XCTAssertEqual(clipboard.restore(token: "b", changeCount: 3), "original")
    }

    func testOutOfOrderAndDuplicateCallbacksCannotRestoreStaleAudio() {
        var clipboard = ClipboardTransaction<String>()
        clipboard.preparePaste(snapshot: "original", changeCount: 1)
        clipboard.didWrite(token: "a", changeCount: 2)
        clipboard.preparePaste(snapshot: "audio-a", changeCount: 2)
        clipboard.didWrite(token: "b", changeCount: 3)
        XCTAssertEqual(clipboard.restore(token: "b", changeCount: 3), "original")
        XCTAssertNil(clipboard.restore(token: "a", changeCount: 4))
        XCTAssertNil(clipboard.restore(token: "b", changeCount: 4))
    }

    func testUserCopyDuringPendingRestoreIsNeverOverwritten() {
        var clipboard = ClipboardTransaction<String>()
        clipboard.preparePaste(snapshot: "original", changeCount: 1)
        clipboard.didWrite(token: "a", changeCount: 2)
        XCTAssertNil(clipboard.restore(token: "a", changeCount: 3))
    }

    func testUserCopyBecomesBaselineForNextPaste() {
        var clipboard = ClipboardTransaction<String>()
        clipboard.preparePaste(snapshot: "original", changeCount: 1)
        clipboard.didWrite(token: "a", changeCount: 2)
        clipboard.preparePaste(snapshot: "user-copy", changeCount: 3)
        clipboard.didWrite(token: "b", changeCount: 4)
        XCTAssertNil(clipboard.restore(token: "a", changeCount: 4))
        XCTAssertEqual(clipboard.restore(token: "b", changeCount: 4), "user-copy")
    }

    func testCancelOrStartFailureOfNextRecordingDoesNotRestorePendingPaste() {
        var clipboard = ClipboardTransaction<String>()
        clipboard.preparePaste(snapshot: "original", changeCount: 1)
        clipboard.didWrite(token: "a", changeCount: 2)
        XCTAssertNil(clipboard.restore(token: "b", changeCount: 2))
        XCTAssertEqual(clipboard.restore(token: "a", changeCount: 2), "original")
    }

    func testRestoreWhileNextRecordingRunsThenPasteUsesRestoredClipboard() {
        var clipboard = ClipboardTransaction<String>()
        clipboard.preparePaste(snapshot: "original", changeCount: 1)
        clipboard.didWrite(token: "a", changeCount: 2)
        XCTAssertEqual(clipboard.restore(token: "a", changeCount: 2), "original")
        clipboard.preparePaste(snapshot: "original", changeCount: 3)
        clipboard.didWrite(token: "b", changeCount: 4)
        XCTAssertEqual(clipboard.restore(token: "b", changeCount: 4), "original")
    }

    func testEmptyClipboardAndFailedWriteCanBeRestored() {
        var clipboard = ClipboardTransaction<[String]>()
        clipboard.preparePaste(snapshot: [], changeCount: 1)
        // Clearing the pasteboard is already an owned write, even if writeObjects fails.
        clipboard.didWrite(token: "a", changeCount: 2)
        XCTAssertEqual(clipboard.restore(token: "a", changeCount: 2), [])
    }
}
