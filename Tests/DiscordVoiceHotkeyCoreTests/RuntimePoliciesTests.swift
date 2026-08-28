import XCTest
@testable import DiscordVoiceHotkeyCore

final class RuntimePoliciesTests: XCTestCase {
    func testImmediateRestoreUsesApplicationsPasteChangeCount() {
        XCTAssertEqual(
            ClipboardRestorePolicy.expectedChangeCount(
                originalChangeCount: 10,
                applicationPasteChangeCount: 12
            ),
            12
        )
    }

    func testImmediateRestoreFallsBackToOriginalWhenAppNeverChangedClipboard() {
        XCTAssertEqual(
            ClipboardRestorePolicy.expectedChangeCount(
                originalChangeCount: 10,
                applicationPasteChangeCount: nil
            ),
            10
        )
    }

    func testRetriesSameHotKeyWhenNoRegistrationIsActive() {
        XCTAssertTrue(
            HotKeyRegistrationPolicy.shouldAttemptRegistration(
                configurationChanged: false,
                hasActiveRegistration: false
            )
        )
    }

    func testDoesNotReregisterUnchangedActiveHotKey() {
        XCTAssertFalse(
            HotKeyRegistrationPolicy.shouldAttemptRegistration(
                configurationChanged: false,
                hasActiveRegistration: true
            )
        )
    }

    func testRejectsHeaderOnlyRecordingWithoutAudioFrames() {
        XCTAssertFalse(
            RecordingOutputPolicy.isUsable(fileSize: 2_048, audioFrameCount: 0)
        )
    }

    func testAcceptsRecordingWithFileDataAndAudioFrames() {
        XCTAssertTrue(
            RecordingOutputPolicy.isUsable(fileSize: 2_048, audioFrameCount: 1_024)
        )
    }
}
