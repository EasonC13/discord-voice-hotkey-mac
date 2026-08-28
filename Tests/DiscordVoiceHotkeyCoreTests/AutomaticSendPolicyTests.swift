import XCTest
@testable import DiscordVoiceHotkeyCore

final class AutomaticSendPolicyTests: XCTestCase {
    func testAutomaticSendDelayIsAtMostTwoTenthsOfASecond() {
        XCTAssertEqual(AutomaticSendPolicy.sendDelay, 0.2, accuracy: 0.001)
    }

    func testSendsWhenEnabledAndOriginalTargetStillHasFocus() {
        XCTAssertTrue(
            AutomaticSendPolicy.shouldSend(
                isEnabled: true,
                frontmostApplicationPID: 42,
                targetApplicationPID: 42
            )
        )
    }

    func testDoesNotSendWhenFeatureIsDisabled() {
        XCTAssertFalse(
            AutomaticSendPolicy.shouldSend(
                isEnabled: false,
                frontmostApplicationPID: 42,
                targetApplicationPID: 42
            )
        )
    }

    func testDoesNotPressEnterAfterFocusMovesToAnotherApplication() {
        XCTAssertFalse(
            AutomaticSendPolicy.shouldSend(
                isEnabled: true,
                frontmostApplicationPID: 99,
                targetApplicationPID: 42
            )
        )
    }

    func testDoesNotSendWithoutAKnownPasteTarget() {
        XCTAssertFalse(
            AutomaticSendPolicy.shouldSend(
                isEnabled: true,
                frontmostApplicationPID: 42,
                targetApplicationPID: nil
            )
        )
    }
}
