import XCTest
@testable import DiscordVoiceHotkeyCore

final class TranscriptionShortcutTests: XCTestCase {
    func testHeldShortcutOnlyFiresOncePerPressReleaseCycle() {
        var latch = HotKeyPressLatch()
        XCTAssertTrue(latch.receive(isPressed: true))
        XCTAssertFalse(latch.receive(isPressed: true))
        XCTAssertFalse(latch.receive(isPressed: false))
        XCTAssertTrue(latch.receive(isPressed: true))
    }

    func testAssignedAudioChordWinsRegardlessOfDisplayName() {
        XCTAssertTrue(TranscriptionShortcut.conflictsWithAudio(keyCode: 18, modifiers: 4096))
        XCTAssertFalse(TranscriptionShortcut.conflictsWithAudio(keyCode: 18, modifiers: 4352))
        XCTAssertFalse(TranscriptionShortcut.conflictsWithAudio(keyCode: 15, modifiers: 4096))
    }
}
