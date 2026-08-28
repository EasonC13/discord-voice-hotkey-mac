public enum ClipboardRestorePolicy {
    public static func expectedChangeCount(
        originalChangeCount: Int,
        applicationPasteChangeCount: Int?
    ) -> Int {
        applicationPasteChangeCount ?? originalChangeCount
    }
}

public enum HotKeyRegistrationPolicy {
    public static func shouldAttemptRegistration(
        configurationChanged: Bool,
        hasActiveRegistration: Bool
    ) -> Bool {
        configurationChanged || !hasActiveRegistration
    }
}

public enum RecordingOutputPolicy {
    public static func isUsable(fileSize: Int, audioFrameCount: Int64) -> Bool {
        fileSize > 512 && audioFrameCount > 0
    }
}
