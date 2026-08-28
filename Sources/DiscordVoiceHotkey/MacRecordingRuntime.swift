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
    }

    private var recorder: AVAudioRecorder?
    private var snapshots: [String: ClipboardSnapshot] = [:]
    private var lastPasteboardChangeCount: Int?
    private var lastOutputURL: URL?

    var microphoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var accessibilityAuthorized: Bool {
        AXIsProcessTrusted()
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
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
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
            lastOutputURL = url
        } catch let error as RuntimeError {
            throw error
        } catch {
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
            lastOutputURL = nil
            return nil
        }

        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 512 else {
            try? FileManager.default.removeItem(at: url)
            lastOutputURL = nil
            return nil
        }
        return url
    }

    func activateApplication(pid: Int32?) {
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
        pasteboard.clearContents()
        guard pasteboard.writeObjects([url as NSURL]) else {
            throw RuntimeError.pasteboardWrite
        }
        lastPasteboardChangeCount = pasteboard.changeCount

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw RuntimeError.keyEventCreation
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1_800) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func restoreClipboardNow(token: String) {
        restoreClipboard(token: token, onlyIfChangeCountIs: nil)
    }

    func restoreClipboardLater(token: String) {
        let expectedChangeCount = lastPasteboardChangeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.restoreClipboard(token: token, onlyIfChangeCountIs: expectedChangeCount)
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
            return ClipboardSnapshot(items: [], wasEmpty: true)
        }

        let items = pasteboardItems.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        return ClipboardSnapshot(items: items, wasEmpty: false)
    }

    private func restoreClipboard(token: String, onlyIfChangeCountIs expected: Int?) {
        guard let snapshot = snapshots.removeValue(forKey: token) else { return }
        let pasteboard = NSPasteboard.general
        if let expected, pasteboard.changeCount != expected {
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

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }
}
