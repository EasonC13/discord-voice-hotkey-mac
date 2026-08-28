import AppKit
import Carbon

final class ShortcutCaptureWindowController: NSWindowController, NSWindowDelegate {
    private let onCapture: (HotKeyConfiguration) throws -> Void
    private var monitor: Any?
    private let promptLabel = NSTextField(labelWithString: "Press a new shortcut")
    private let detailLabel = NSTextField(labelWithString: "Use at least one modifier: Control, Option, Shift, or Command.")

    init(onCapture: @escaping (HotKeyConfiguration) throws -> Void) {
        self.onCapture = onCapture

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Change Recording Shortcut"
        panel.isReleasedWhenClosed = false
        panel.center()

        super.init(window: panel)
        panel.delegate = self
        buildContent(in: panel)
    }

    required init?(coder: NSCoder) { nil }

    private func buildContent(in panel: NSPanel) {
        guard let content = panel.contentView else { return }

        promptLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        promptLabel.alignment = .center
        promptLabel.frame = NSRect(x: 24, y: 98, width: 412, height: 34)
        content.addSubview(promptLabel)

        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.frame = NSRect(x: 24, y: 65, width: 412, height: 22)
        content.addSubview(detailLabel)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelCapture))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.frame = NSRect(x: 180, y: 20, width: 100, height: 32)
        content.addSubview(cancel)
    }

    func beginCapture() {
        promptLabel.stringValue = "Press a new shortcut"
        detailLabel.stringValue = "Use at least one modifier: Control, Option, Shift, or Command."
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            closeCapture()
            return
        }

        guard let configuration = HotKeyConfiguration.from(event: event) else {
            NSSound.beep()
            detailLabel.stringValue = "Please include at least one modifier key."
            return
        }

        do {
            try onCapture(configuration)
            closeCapture()
        } catch {
            NSSound.beep()
            promptLabel.stringValue = "Shortcut unavailable"
            detailLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func cancelCapture() {
        closeCapture()
    }

    private func closeCapture() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        close()
    }

    func windowWillClose(_ notification: Notification) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
