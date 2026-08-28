import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import DiscordVoiceHotkeyCore

final class MacRecordingRuntime: NSObject, RecordingSessionRuntime {
    enum RuntimeError: LocalizedError {
        case microphonePermission
        case recorderCreation
        case recorderStart
        case emptyRecording
        case accessibilityPermission
        case pasteboardWrite
        case keyEventCreation

        var errorDescription: String? {
            switch self {
            case .microphonePermission:
                return "Microphone access is required. Enable it in System Settings → Privacy & Security → Microphone."
            case .recorderCreation:
                return "The audio recorder could not be created."
            case .recorderStart:
                return "Recording could not start. Check your microphone input."
            case .emptyRecording:
                return "No usable audio was recorded."
            case .accessibilityPermission:
                return "Accessibility access is required to paste into Discord."
            case .pasteboardWrite:
                return "The audio file could not be placed on the clipboard."
            case .keyEventCreation:
                return "The Command-V keyboard event could not be created."
            }
        }
    }

    private struct ClipboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
        let wasEmpty: Bool
        let originalChangeCount: Int
    }

    private var recorder: AVAudioRecorder?
    private var snapshots: [String: ClipboardSnapshot] = [:]
    private var pasteChangeCounts: [String: Int] = [:]
    private var activeClipboardToken: String?
    private var lastExternalApplicationPID: Int32?
    private var pasteTargetApplicationPID: Int32?
    private var automaticSendEnabled = true
    private var pendingAutomaticSendID: UUID?
    private var pendingAutomaticSendTargetPID: Int32?
    private var automaticSendFocusWasInterrupted = false

    override init() {
        super.init()
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        removeAllRecordings()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    var microphoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var accessibilityAuthorized: Bool {
        AXIsProcessTrusted()
    }

    func setAutomaticSendEnabled(_ enabled: Bool) {
        automaticSendEnabled = enabled
        if !enabled {
            clearPendingAutomaticSend()
        }
    }

    func requestInitialPermissions() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func captureContext(at date: Date) -> RecordingContext {
        let token = UUID().uuidString
        snapshots[token] = captureClipboard()
        activeClipboardToken = token
        let frontmost = NSWorkspace.shared.frontmostApplication
        let pid = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            ? lastExternalApplicationPID
            : frontmost?.processIdentifier
        return RecordingContext(
            clipboardToken: token,
            frontmostApplicationPID: pid,
            startedAt: date
        )
    }

    func startRecording() throws {
        guard microphoneAuthorized else { throw RuntimeError.microphonePermission }

        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiscordVoiceHotkey", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "voice-\(Self.timestamp()).m4a"
        let url = directory.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            guard recorder.record() else { throw RuntimeError.recorderStart }
            self.recorder = recorder
        } catch let error as RuntimeError {
            deleteRecording(at: url)
            throw error
        } catch {
            deleteRecording(at: url)
            throw RuntimeError.recorderCreation
        }
    }

    func stopRecording(cancel: Bool) -> URL? {
        guard let recorder else { return nil }
        let url = recorder.url
        recorder.stop()
        self.recorder = nil

        if cancel {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let frameCount = (try? AVAudioFile(forReading: url).length) ?? 0
        guard RecordingOutputPolicy.isUsable(
            fileSize: size,
            audioFrameCount: frameCount
        ) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    func activateApplication(pid: Int32?) {
        pasteTargetApplicationPID = pid
        guard let pid,
              let application = NSRunningApplication(processIdentifier: pid) else { return }
        application.activate(options: [.activateIgnoringOtherApps])
    }

    func pasteAudioFile(_ url: URL) throws {
        guard accessibilityAuthorized else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            throw RuntimeError.accessibilityPermission
        }

        Thread.sleep(forTimeInterval: 0.2)
        let pasteboard = NSPasteboard.general
        if let token = activeClipboardToken,
           let snapshot = snapshots[token],
           ClipboardSnapshotPolicy.shouldRefreshSnapshot(
               originalChangeCount: snapshot.originalChangeCount,
               currentChangeCount: pasteboard.changeCount
           ) {
            snapshots[token] = captureClipboard()
        }
        pasteboard.clearContents()
        if let activeClipboardToken {
            pasteChangeCounts[activeClipboardToken] = pasteboard.changeCount
        }
        guard pasteboard.writeObjects([url as NSURL]) else {
            throw RuntimeError.pasteboardWrite
        }
        if let activeClipboardToken {
            pasteChangeCounts[activeClipboardToken] = pasteboard.changeCount
        }

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw RuntimeError.keyEventCreation
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        if automaticSendEnabled, let targetPID = pasteTargetApplicationPID {
            let sendID = UUID()
            pendingAutomaticSendID = sendID
            pendingAutomaticSendTargetPID = targetPID
            automaticSendFocusWasInterrupted = false
            DispatchQueue.main.asyncAfter(deadline: .now() + AutomaticSendPolicy.sendDelay) { [weak self] in
                self?.sendReturnIfSafe(sendID: sendID)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1_800) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func sendReturnIfSafe(sendID: UUID) {
        guard pendingAutomaticSendID == sendID else { return }
        defer { clearPendingAutomaticSend() }

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let targetPID = pendingAutomaticSendTargetPID,
              AutomaticSendPolicy.shouldSend(
                  isEnabled: automaticSendEnabled,
                  focusWasInterrupted: automaticSendFocusWasInterrupted,
                  frontmostApplicationPID: frontmostPID,
                  targetApplicationPID: targetPID
              ),
              let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) else {
            return
        }
        keyDown.postToPid(targetPID)
        keyUp.postToPid(targetPID)
    }

    private func clearPendingAutomaticSend() {
        pendingAutomaticSendID = nil
        pendingAutomaticSendTargetPID = nil
        automaticSendFocusWasInterrupted = false
    }

    func deleteRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func shutdownRecordingStorage() {
        clearPendingAutomaticSend()
        cancelActiveRecording()
        for token in Array(snapshots.keys) {
            restoreClipboardNow(token: token)
        }
        removeAllRecordings()
    }

    func restoreClipboardNow(token: String) {
        restoreClipboard(token: token, onlyIfChangeCountIs: pasteChangeCounts[token])
    }

    func restoreClipboardLater(token: String, completion: @escaping () -> Void) {
        let expectedChangeCount = pasteChangeCounts[token]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.restoreClipboard(token: token, onlyIfChangeCountIs: expectedChangeCount)
            completion()
        }
    }

    func openMicrophoneSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    func openAccessibilitySettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func cancelActiveRecording() {
        guard let recorder else { return }
        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        try? FileManager.default.removeItem(at: url)
    }

    private func captureClipboard() -> ClipboardSnapshot {
        let pasteboard = NSPasteboard.general
        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else {
            return ClipboardSnapshot(
                items: [],
                wasEmpty: true,
                originalChangeCount: pasteboard.changeCount
            )
        }

        let items = pasteboardItems.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        return ClipboardSnapshot(
            items: items,
            wasEmpty: false,
            originalChangeCount: pasteboard.changeCount
        )
    }

    private func restoreClipboard(token: String, onlyIfChangeCountIs expected: Int?) {
        guard let snapshot = snapshots.removeValue(forKey: token) else { return }
        pasteChangeCounts.removeValue(forKey: token)
        if activeClipboardToken == token { activeClipboardToken = nil }

        let pasteboard = NSPasteboard.general
        let safeChangeCount = ClipboardRestorePolicy.expectedChangeCount(
            originalChangeCount: snapshot.originalChangeCount,
            applicationPasteChangeCount: expected
        )
        if pasteboard.changeCount != safeChangeCount {
            return
        }

        pasteboard.clearContents()
        guard !snapshot.wasEmpty else { return }
        let items = snapshot.items.map { stored -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in stored {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private func openSettings(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if pendingAutomaticSendID != nil,
           application?.processIdentifier != pendingAutomaticSendTargetPID {
            automaticSendFocusWasInterrupted = true
        }
        rememberExternalApplication(application)
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastExternalApplicationPID = application.processIdentifier
    }

    private func removeAllRecordings() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private var recordingsDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiscordVoiceHotkey", isDirectory: true)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }
}
