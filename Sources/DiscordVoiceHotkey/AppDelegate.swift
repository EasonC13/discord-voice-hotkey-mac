import AppKit
import DiscordVoiceHotkeyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let runtime = MacRecordingRuntime()
    // Inject the approved standalone adapter here; nil never records or makes a request.
    private lazy var transcription = TranscriptionFlow(provider: nil, delivery: MacTranscriptDelivery(runtime: runtime))
    private lazy var machine = RecordingSessionMachine(runtime: runtime, transcription: transcription)
    private var statusItem: NSStatusItem!
    private var startStopItem: NSMenuItem!
    private var shortcutItem: NSMenuItem!
    private var automaticSendItem: NSMenuItem!
    private var microphoneItem: NSMenuItem!
    private var accessibilityItem: NSMenuItem!
    private var hotKey: GlobalHotKey?
    private var transcriptHotKey: GlobalHotKey?
    private var transcriptStatusItem: NSMenuItem!
    private var recoveryItem: NSMenuItem!
    private var transcriptNotice: String?
    private var hotKeyConfiguration = HotKeyConfiguration.load()
    private var shortcutCapture: ShortcutCaptureWindowController?
    private var automaticSendEnabled: Bool = {
        let defaults = UserDefaults.standard
        let key = "automaticSendEnabled"
        return defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        runtime.setAutomaticSendEnabled(automaticSendEnabled)
        configureStatusItem()
        registerHotKey(hotKeyConfiguration, showErrorOnFailure: true)
        registerTranscriptHotKey()
        transcription.onChange = { [weak self] in self?.refreshMenu() }
        refreshMenu()
        runtime.requestInitialPermissions()
        showFirstLaunchHelpIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        machine.shutdown()
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

        automaticSendItem = NSMenuItem(
            title: "Send Automatically After Paste",
            action: #selector(toggleAutomaticSend),
            keyEquivalent: ""
        )
        automaticSendItem.target = self
        menu.addItem(automaticSendItem)

        transcriptStatusItem = NSMenuItem(title: "Transcription", action: nil, keyEquivalent: "")
        menu.addItem(transcriptStatusItem)
        recoveryItem = NSMenuItem(title: "Recover Transcripts", action: nil, keyEquivalent: "")
        menu.addItem(recoveryItem)

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
        toggleRecording(mode: .audio)
    }

    private func toggleRecording(mode: RecordingMode) {
        do {
            if mode == .transcript { transcriptNotice = nil }
            try machine.toggle(mode: mode)
            updateStatusAppearance()
            refreshMenu()
        } catch {
            updateStatusAppearance()
            refreshMenu()
            if mode == .audio {
                showError(error.localizedDescription)
            } else {
                transcriptNotice = error.localizedDescription
                refreshMenu()
            }
        }
    }

    @objc private func changeShortcut() {
        guard !machine.isRecording else { return }
        if shortcutCapture == nil {
            shortcutCapture = ShortcutCaptureWindowController { [weak self] configuration in
                guard let self else { return }
                try self.applyHotKey(configuration)
            }
        }
        shortcutCapture?.beginCapture()
    }

    @objc private func toggleAutomaticSend() {
        automaticSendEnabled.toggle()
        UserDefaults.standard.set(automaticSendEnabled, forKey: "automaticSendEnabled")
        runtime.setAutomaticSendEnabled(automaticSendEnabled)
        refreshMenu()
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
        alert.informativeText = "A native menu bar recorder for macOS.\n\nPress \(hotKeyConfiguration.displayName) to start recording, then press it again to paste an M4A audio attachment and send it automatically after 0.2 seconds."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func applyHotKey(_ configuration: HotKeyConfiguration) throws {
        guard !machine.isRecording else { return }
        guard HotKeyRegistrationPolicy.shouldAttemptRegistration(
            configurationChanged: configuration != hotKeyConfiguration,
            hasActiveRegistration: hotKey != nil
        ) else { return }
        let needsTranscriptSlot = TranscriptionShortcut.conflictsWithAudio(
            keyCode: configuration.keyCode, modifiers: configuration.carbonModifiers)
        if needsTranscriptSlot { transcriptHotKey = nil }
        let replacement: GlobalHotKey
        do {
            replacement = try GlobalHotKey(configuration: configuration) { [weak self] in
                self?.toggleRecording()
            }
        } catch {
            if needsTranscriptSlot { registerTranscriptHotKey() }
            throw error
        }
        hotKey = replacement
        hotKeyConfiguration = configuration
        configuration.save()
        registerTranscriptHotKey()
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

    private var transcriptShortcutConflicts: Bool {
        TranscriptionShortcut.conflictsWithAudio(keyCode: hotKeyConfiguration.keyCode,
                                                modifiers: hotKeyConfiguration.carbonModifiers)
    }

    private func registerTranscriptHotKey() {
        guard !transcriptShortcutConflicts, transcriptHotKey == nil else { return }
        transcriptHotKey = try? GlobalHotKey(configuration: HotKeyConfiguration(
            keyCode: TranscriptionShortcut.keyCode, carbonModifiers: TranscriptionShortcut.modifiers,
            displayName: "⌃1"
        )) { [weak self] in self?.toggleRecording(mode: .transcript) }
    }

    @objc private func copyRecovery(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID,
              let entry = transcription.recoveries.first(where: { $0.id == id }) else { return }
        let board = NSPasteboard.general
        board.clearContents()
        if board.setString(entry.text, forType: .string) { transcription.discardRecovery(id) }
    }

    private func updateStatusAppearance() {
        guard let button = statusItem?.button else { return }
        let symbol = StatusIconPolicy.symbolName(isRecording: machine.isRecording)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Discord Voice Hotkey")
        button.image?.isTemplate = true
        button.contentTintColor = StatusIconPolicy.usesExplicitTint(isRecording: machine.isRecording)
            ? .systemRed
            : nil
        button.toolTip = machine.recordingMode == .transcript ? "Recording transcript… Press ⌃1 to stop" : machine.isRecording
            ? "Recording… Press \(hotKeyConfiguration.displayName) to stop"
            : "Press \(hotKeyConfiguration.displayName) to record"
    }

    private func refreshMenu() {
        startStopItem?.isEnabled = machine.recordingMode != .transcript
        shortcutItem?.isEnabled = !machine.isRecording
        startStopItem?.title = machine.recordingMode == .transcript ? "Recording Transcript  ⌃1" : machine.isRecording
            ? (automaticSendEnabled
                ? "Stop, Paste, and Send  \(hotKeyConfiguration.displayName)"
                : "Stop and Paste  \(hotKeyConfiguration.displayName)")
            : "Start Recording  \(hotKeyConfiguration.displayName)"
        shortcutItem?.title = "Change Shortcut…  (Current: \(hotKeyConfiguration.displayName))"
        automaticSendItem?.title = "Send Audio Automatically After Paste (0.2s)"
        automaticSendItem?.state = automaticSendEnabled ? .on : .off
        microphoneItem?.title = runtime.microphoneAuthorized
            ? "✓ Microphone Allowed"
            : "⚠ Enable Microphone…"
        accessibilityItem?.title = runtime.accessibilityAuthorized
            ? "✓ Accessibility Allowed"
            : "⚠ Enable Accessibility…"
        if transcriptShortcutConflicts {
            transcriptStatusItem?.title = "Transcription Unavailable — ⌃1 Is Assigned to Audio"
        } else if transcriptHotKey == nil {
            transcriptStatusItem?.title = "Transcription Unavailable — Could Not Register ⌃1"
        } else if let transcriptNotice {
            transcriptStatusItem?.title = transcriptNotice
        } else if transcription.pendingCount > 0 {
            transcriptStatusItem?.title = "Transcribing… (\(transcription.pendingCount))"
        } else {
            switch transcription.status {
            case .unavailable: transcriptStatusItem?.title = "Transcription Not Configured  ⌃1"
            case .idle, .transcribing: transcriptStatusItem?.title = "Transcription Shortcut  ⌃1"
            case .delivered: transcriptStatusItem?.title = "Transcript Submitted to Discord"
            case .recoverable: transcriptStatusItem?.title = "Transcript Ready to Copy"
            case .failed: transcriptStatusItem?.title = "Transcription Failed"
            }
        }
        recoveryItem?.isHidden = transcription.recoveries.isEmpty
        let recoveryMenu = NSMenu()
        for (index, recovery) in transcription.recoveries.enumerated() {
            let item = NSMenuItem(title: "Copy Transcript \(index + 1)", action: #selector(copyRecovery(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = recovery.id
            recoveryMenu.addItem(item)
        }
        recoveryItem?.submenu = recoveryMenu
    }

    private func showFirstLaunchHelpIfNeeded() {
        let key = "didShowFirstLaunchHelp"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = "Discord Voice Hotkey is ready"
            alert.informativeText = "The microphone icon now lives in your menu bar.\n\nPress \(self.hotKeyConfiguration.displayName) once to record and again to paste and automatically send the audio attachment. You can change the shortcut or disable automatic sending from the menu bar."
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
