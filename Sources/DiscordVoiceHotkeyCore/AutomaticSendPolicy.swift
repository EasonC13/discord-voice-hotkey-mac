import Foundation

public enum AutomaticSendPolicy {
    public static let sendDelay: TimeInterval = 0.2

    public static func shouldSend(
        isEnabled: Bool,
        focusWasInterrupted: Bool,
        frontmostApplicationPID: Int32?,
        targetApplicationPID: Int32?
    ) -> Bool {
        guard isEnabled, !focusWasInterrupted, let targetApplicationPID else { return false }
        return frontmostApplicationPID == targetApplicationPID
    }
}
