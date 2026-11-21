public enum TranscriptionShortcut {
    public static let keyCode: UInt32 = 18 // ANSI 1
    public static let modifiers: UInt32 = 1 << 12 // Carbon controlKey

    public static func conflictsWithAudio(keyCode: UInt32, modifiers: UInt32) -> Bool {
        keyCode == Self.keyCode && modifiers == Self.modifiers
    }
}

public struct HotKeyPressLatch {
    private var isDown = false
    public init() {}

    public mutating func receive(isPressed: Bool) -> Bool {
        let shouldFire = isPressed && !isDown
        isDown = isPressed
        return shouldFire
    }
}
