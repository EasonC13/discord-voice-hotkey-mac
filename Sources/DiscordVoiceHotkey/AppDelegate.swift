import AppKit
import DiscordVoiceHotkeyCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let runtime = MacRecordingRuntime()
    private lazy var machine = RecordingSessionMachine(runtime: runtime)
    private var statusItem: NSStatusItem!
    private var startStopItem: NSMenuItem!
    private var shortcutItem: NSMenuItem!
    private var microphoneItem: NSMenuItem!
    private var accessibilityItem: NSMenuItem!
    private var hotKey: GlobalHotKey?
    private var hotKeyConfiguration = HotKeyConfiguration.load()
    private var shortcutCapture: ShortcutCaptureWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        registerHotKey(hotKeyConfiguration, showErrorOnFailure: true)
        runtime.requestInitialPermissions()
        showFirstLaunchHelpIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.cancelActiveRecording()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusAppearance()

        let menu = NSMenu()
        menu.delegate = self

        startStopItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        startStopItem.target = self
        menu.addItem(startStopItem)

        shortcutItem = NSMenuItem(
            title: "Change Shortcut…",
            action: #selector(changeShortcut),
            keyEquivalent: ""
        )
        shortcutItem.target = self
        menu.addItem(shortcutItem)

        menu.addItem(.separator())

        microphoneItem = NSMenuItem(
            title: "Microphone Permission",
            action: #selector(openMicrophoneSettings),
            keyEquivalent: ""
        )
        microphoneItem.target = self
        menu.addItem(microphoneItem)

        accessibilityItem = NSMenuItem(
            title: "Accessibility Permission",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Discord Voice Hotkey", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit", action: #selector(quitApplication), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        refreshMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu()
    }

    @objc private func toggleRecording() {
        do {
            try machine.toggle()
            updateStatusAppearance()
            refreshMenu()
        } catch {
            updateStatusAppearance()
            refreshMenu()
            showError(error.localizedDescription)
        }
    }

    @objc private func changeShortcut() {
        if shortcutCapture == nil {
            shortcutCapture = ShortcutCaptureWindowController { [weak self] configuration in
                guard let self else { return }
                try self.applyHotKey(configuration)
            }
        }
        shortcutCapture?.beginCapture()
    }

    @objc private func openMicrophoneSettings() {
        runtime.openMicrophoneSettings()
    }

    @objc private func openAccessibilitySettings() {
        runtime.openAccessibilitySettings()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Discord Voice Hotkey"
        alert.informativeText = "A native menu bar recorder for macOS.\n\nPress \(hotKeyConfiguration.displayName) to start recording, then press it again to paste an M4A audio attachment into the app that was active when recording began."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func applyHotKey(_ configuration: HotKeyConfiguration) throws {
        if configuration == hotKeyConfiguration { return }
        let replacement = try GlobalHotKey(configuration: configuration) { [weak self] in
            self?.toggleRecording()
        }
        hotKey = replacement
        hotKeyConfiguration = configuration
        configuration.save()
        refreshMenu()
    }

    private func registerHotKey(_ configuration: HotKeyConfiguration, showErrorOnFailure: Bool) {
        do {
            hotKey = try GlobalHotKey(configuration: configuration) { [weak self] in
                self?.toggleRecording()
            }
        } catch {
            if showErrorOnFailure { showError(error.localizedDescription) }
        }
    }

    private func updateStatusAppearance() {
        guard let button = statusItem?.button else { return }
        let symbol = machine.isRecording ? "record.circle.fill" : "mic.circle"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Discord Voice Hotkey")
        button.image?.isTemplate = !machine.isRecording
        button.contentTintColor = machine.isRecording ? .systemRed : .labelColor
        button.toolTip = machine.isRecording
            ? "Recording… Press \(hotKeyConfiguration.displayName) to stop"
            : "Press \(hotKeyConfiguration.displayName) to record"
    }

    private func refreshMenu() {
        startStopItem?.title = machine.isRecording
            ? "Stop and Paste  \(hotKeyConfiguration.displayName)"
            : "Start Recording  \(hotKeyConfiguration.displayName)"
        shortcutItem?.title = "Change Shortcut…  (Current: \(hotKeyConfiguration.displayName))"
        microphoneItem?.title = runtime.microphoneAuthorized
            ? "✓ Microphone Allowed"
            : "⚠ Enable Microphone…"
        accessibilityItem?.title = runtime.accessibilityAuthorized
            ? "✓ Accessibility Allowed"
            : "⚠ Enable Accessibility…"
    }

    private func showFirstLaunchHelpIfNeeded() {
        let key = "didShowFirstLaunchHelp"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = "Discord Voice Hotkey is ready"
            alert.informativeText = "The microphone icon now lives in your menu bar.\n\nPress \(self.hotKeyConfiguration.displayName) once to record and again to paste the audio attachment. You can change the shortcut from the menu bar at any time."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Got it")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Discord Voice Hotkey"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
