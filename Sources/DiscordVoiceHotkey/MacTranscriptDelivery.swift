import AppKit
import ApplicationServices
import DiscordVoiceHotkeyCore

@MainActor
final class MacTranscriptDelivery: TranscriptDelivery {
    /// A supported Discord AX adapter must positively identify the message composer,
    /// verify absence of staged attachments and issue a revision that changes on any
    /// observed target interruption (including away-and-back). Unknown means nil.
    /// An empty AXValue, title match or lack of attachment nodes isn't that proof.
    typealias ComposerProof = (_ app: NSRunningApplication, _ window: AXUIElement,
                               _ composer: AXUIElement, _ webArea: AXUIElement) -> UUID?

    private struct Snapshot {
        let pid: Int32
        let launched: Date
        let window: AXUIElement
        let composer: AXUIElement
        let webArea: AXUIElement
        let channel: String
        let workspaceRevision: UUID
        let composerRevision: UUID

        func matches(_ other: Snapshot) -> Bool {
            pid == other.pid && launched == other.launched && channel == other.channel &&
            workspaceRevision == other.workspaceRevision && composerRevision == other.composerRevision &&
            CFEqual(window, other.window) && CFEqual(composer, other.composer) && CFEqual(webArea, other.webArea)
        }
    }

    private let runtime: MacRecordingRuntime
    private let composerProof: ComposerProof?
    private var targets: [UUID: Snapshot] = [:]
    private static let discordBundles: Set<String> = ["com.hnc.Discord", "com.hnc.DiscordPTB", "com.hnc.DiscordCanary"]

    init(runtime: MacRecordingRuntime, composerProof: ComposerProof? = nil) {
        self.runtime = runtime
        self.composerProof = composerProof
    }

    func captureTarget() -> TranscriptTarget? {
        guard let snapshot = observe(expectedText: "") else { return nil }
        let id = UUID()
        targets[id] = snapshot
        return TranscriptTarget(pid: snapshot.pid, identity: id)
    }

    func validate(_ target: TranscriptTarget, expectedText: String) -> Bool {
        guard let original = targets[target.identity], original.pid == target.pid,
              let current = observe(expectedText: expectedText) else { return false }
        return original.matches(current)
    }

    func paste(_ text: String, into target: TranscriptTarget, token: UUID) -> Bool {
        runtime.pasteTranscript(text, pid: target.pid, token: token) { validate(target, expectedText: "") }
    }

    func send(to target: TranscriptTarget, token: UUID, expectedText: String) -> Bool {
        runtime.sendTranscript(pid: target.pid, token: token) { validate(target, expectedText: expectedText) }
    }

    func release(_ target: TranscriptTarget) { targets[target.identity] = nil }
    func deleteAudio(_ url: URL) { runtime.deleteRecording(at: url) }

    private func observe(expectedText: String) -> Snapshot? {
        guard let composerProof, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication, let bundle = app.bundleIdentifier,
              Self.discordBundles.contains(bundle), let launched = app.launchDate else { return nil }
        let pid = app.processIdentifier
        let workspaceRevision = runtime.applicationActivationRevision
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.1)
        guard let window = element(axApp, kAXFocusedWindowAttribute),
              let composer = element(axApp, kAXFocusedUIElementAttribute),
              let composerWindow = element(composer, kAXWindowAttribute), CFEqual(window, composerWindow),
              let role = attribute(composer, kAXRoleAttribute) as? String, role == kAXTextAreaRole,
              let value = attribute(composer, kAXValueAttribute) as? String,
              value.utf16.elementsEqual(expectedText.utf16),
              let webArea = webAreaAncestor(of: composer),
              let url = attribute(webArea, kAXURLAttribute) as? URL,
              let channel = Self.channelIdentity(url),
              let revision = composerProof(app, window, composer, webArea),
              let finalWindow = element(axApp, kAXFocusedWindowAttribute), CFEqual(window, finalWindow),
              let finalFocus = element(axApp, kAXFocusedUIElementAttribute), CFEqual(composer, finalFocus),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              runtime.applicationActivationRevision == workspaceRevision else { return nil }
        return Snapshot(pid: pid, launched: launched, window: window, composer: composer, webArea: webArea,
                        channel: channel, workspaceRevision: workspaceRevision, composerRevision: revision)
    }

    private static func channelIdentity(_ url: URL) -> String? {
        guard url.scheme == "https", url.host == "discord.com", url.port == nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: false)
        func isID(_ value: Substring) -> Bool {
            !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
        }
        guard segments.count == 4, segments[0].isEmpty, segments[1] == "channels",
              segments[2] == "@me" || isID(segments[2]), isID(segments[3]) else { return nil }
        return url.path
    }

    private func webAreaAncestor(of composer: AXUIElement) -> AXUIElement? {
        var node = composer
        for _ in 0..<12 {
            guard let parent = element(node, kAXParentAttribute) else { return nil }
            if attribute(parent, kAXRoleAttribute) as? String == kAXWebAreaRole { return parent }
            node = parent
        }
        return nil
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private func element(_ owner: AXUIElement, _ name: String) -> AXUIElement? {
        guard let result = attribute(owner, name), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(result, to: AXUIElement.self)
    }
}
