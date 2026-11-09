/// Owns only the latest temporary clipboard write, independently of recording.
/// Call on the same serial executor as the pasteboard operations (the main queue).
public struct ClipboardTransaction<Snapshot> {
    private var baseline: Snapshot?
    private var ownedChangeCount: Int?
    public private(set) var ownerToken: String?

    public init() {}

    /// Snapshot immediately before replacing the clipboard. Reuse the baseline
    /// while it still contains our audio; never snapshot that audio as user data.
    public mutating func preparePaste(snapshot: @autoclosure () -> Snapshot, changeCount: Int) {
        if ownedChangeCount != changeCount {
            baseline = snapshot()
        }
    }

    /// Also call after clearContents: a failed write still needs cleanup.
    public mutating func didWrite(token: String, changeCount: Int) {
        ownerToken = token
        ownedChangeCount = changeCount
    }

    /// Old, duplicate, cancelled and failed-start sessions have no authority over
    /// the newest paste. A genuine external copy always wins over restoration.
    public mutating func restore(token: String, changeCount: Int) -> Snapshot? {
        guard ownerToken == token else { return nil }
        defer {
            baseline = nil
            ownedChangeCount = nil
            ownerToken = nil
        }
        guard ownedChangeCount == changeCount else { return nil }
        return baseline
    }
}
