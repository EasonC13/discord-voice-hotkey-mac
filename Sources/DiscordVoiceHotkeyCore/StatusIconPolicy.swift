public enum StatusIconPolicy {
    public static func symbolName(isRecording: Bool) -> String {
        isRecording ? "record.circle.fill" : "mic.circle.fill"
    }

    public static func usesExplicitTint(isRecording: Bool) -> Bool {
        isRecording
    }
}
