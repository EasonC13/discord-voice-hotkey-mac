import XCTest
@testable import DiscordVoiceHotkeyCore

final class DefaultShortcutTests: XCTestCase {
    func testDefaultShortcutIsControlR() {
        XCTAssertEqual(DefaultShortcut.keyCode, 15)
        XCTAssertEqual(DefaultShortcut.carbonModifiers, 1 << 12)
        XCTAssertEqual(DefaultShortcut.displayName, "⌃R")
    }
}
