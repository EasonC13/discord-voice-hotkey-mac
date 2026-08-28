public enum ClipboardSnapshotPolicy {
    public static func shouldRefreshSnapshot(
        originalChangeCount: Int,
        currentChangeCount: Int
    ) -> Bool {
        originalChangeCount != currentChangeCount
    }
}
