import XCTest
@testable import DiscordVoiceHotkeyCore

final class StatusIconPolicyTests: XCTestCase {
    func testIdleIconUsesFilledHighContrastSymbol() {
        XCTAssertEqual(StatusIconPolicy.symbolName(isRecording: false), "mic.circle.fill")
    }

    func testIdleIconLetsMacOSChooseAdaptiveTemplateColor() {
        XCTAssertFalse(StatusIconPolicy.usesExplicitTint(isRecording: false))
    }

    func testRecordingIconKeepsExplicitRedTint() {
        XCTAssertTrue(StatusIconPolicy.usesExplicitTint(isRecording: true))
    }
}
