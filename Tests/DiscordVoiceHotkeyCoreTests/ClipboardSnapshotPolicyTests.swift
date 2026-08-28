import XCTest
@testable import DiscordVoiceHotkeyCore

final class ClipboardSnapshotPolicyTests: XCTestCase {
    func testRefreshesSnapshotWhenClipboardChangedDuringRecording() {
        XCTAssertTrue(
            ClipboardSnapshotPolicy.shouldRefreshSnapshot(
                originalChangeCount: 10,
                currentChangeCount: 11
            )
        )
    }

    func testKeepsSnapshotWhenClipboardDidNotChangeDuringRecording() {
        XCTAssertFalse(
            ClipboardSnapshotPolicy.shouldRefreshSnapshot(
                originalChangeCount: 10,
                currentChangeCount: 10
            )
        )
    }
}
