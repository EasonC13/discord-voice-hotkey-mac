import AppKit
import Carbon
import DiscordVoiceHotkeyCore

struct HotKeyConfiguration: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let displayName: String

    static let `default` = HotKeyConfiguration(
        keyCode: DefaultShortcut.keyCode,
        carbonModifiers: DefaultShortcut.carbonModifiers,
        displayName: DefaultShortcut.displayName
    )

    static func load() -> HotKeyConfiguration {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "hotKey.keyCode") != nil,
              defaults.object(forKey: "hotKey.modifiers") != nil,
              let displayName = defaults.string(forKey: "hotKey.displayName") else {
            return .default
        }
        return HotKeyConfiguration(
            keyCode: UInt32(defaults.integer(forKey: "hotKey.keyCode")),
            carbonModifiers: UInt32(defaults.integer(forKey: "hotKey.modifiers")),
            displayName: displayName
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: "hotKey.keyCode")
        defaults.set(Int(carbonModifiers), forKey: "hotKey.modifiers")
        defaults.set(displayName, forKey: "hotKey.displayName")
    }

    static func from(event: NSEvent) -> HotKeyConfiguration? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        var glyphs = ""

        if flags.contains(.control) { carbon |= UInt32(controlKey); glyphs += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); glyphs += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); glyphs += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); glyphs += "⌘" }

        guard carbon != 0,
              let characters = event.charactersIgnoringModifiers,
              !characters.isEmpty else { return nil }

        let key = characters.uppercased()
        return HotKeyConfiguration(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: carbon,
            displayName: glyphs + key
        )
    }
}

final class GlobalHotKey {
    enum RegistrationError: LocalizedError {
        case installHandler(OSStatus)
        case register(OSStatus)

        var errorDescription: String? {
            switch self {
            case .installHandler(let status):
                return "Could not install the shortcut handler (\(status))."
            case .register(let status):
                return "That shortcut could not be registered (\(status)). It may be used by another app."
            }
        }
    }

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void

    init(configuration: HotKeyConfiguration, callback: @escaping () -> Void) throws {
        self.callback = callback

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { hotKey.callback() }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &handlerRef
        )
        guard handlerStatus == noErr else {
            throw RegistrationError.installHandler(handlerStatus)
        }

        let identifier = EventHotKeyID(signature: OSType(0x4456484B), id: 1) // DVHK
        let registerStatus = RegisterEventHotKey(
            configuration.keyCode,
            configuration.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            throw RegistrationError.register(registerStatus)
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
