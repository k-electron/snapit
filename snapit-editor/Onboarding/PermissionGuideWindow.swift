import AppKit
import SwiftUI

/// A Permission guide in a window of its own: after an update that took Screen Recording away, when
/// a Capture finds it missing, and when a Save finds its folder closed. One window per kind of
/// guide, like Settings has one: asking for a guide while its window is open brings it forward and
/// has it look again. The helper is a regular app while any of them shows, and quits with the last.
@MainActor
final class PermissionGuideWindow: NSObject, NSWindowDelegate {
    private static var open: [PermissionGuideKind: PermissionGuideWindow] = [:]

    /// The window of this kind of guide, if it is open.
    static func current(_ kind: PermissionGuideKind) -> PermissionGuideWindow? { open[kind] }

    let content: any GuideContent
    private(set) var window: NSWindow?

    private init(content: any GuideContent) {
        self.content = content
        super.init()
    }

    /// Shows the guide of `kind`, built by `makeContent` when none is open for that kind.
    @discardableResult
    static func show(_ kind: PermissionGuideKind, makeContent: () -> any GuideContent) -> PermissionGuideWindow {
        let guide = open[kind] ?? PermissionGuideWindow(content: makeContent())
        open[kind] = guide
        guide.present()
        return guide
    }

    static func showScreenRecording() {
        show(.screenRecording) { PermissionGuideModel(kind: .screenRecording) }
    }

    private func present() {
        if let window {
            HelperLifecycle.windowWillShow()
            window.makeKeyAndOrderFront(nil)
            HelperLifecycle.windowDidShow()
            content.windowResigned()
            Task { await content.windowBecameActive() }
            return
        }
        content.onFinished = { [weak self] in self?.window?.close() }
        let hosting = NSHostingView(rootView: PermissionGuideWindowView(content: content, close: { [weak self] in self?.window?.close() }))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 520, height: 560)),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = content.windowTitle
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = hosting
        window.setContentSize(NSSize(width: 520, height: 560))
        window.center()
        self.window = window

        HelperLifecycle.windowWillShow()
        window.makeKeyAndOrderFront(nil)
        HelperLifecycle.windowDidShow()
        content.isShown = true
        content.isVisible = window.isSeenByUser
        Task { await content.windowBecameActive() }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        Task { await content.windowBecameActive() }
    }

    func windowDidResignKey(_ notification: Notification) {
        content.windowResigned()
    }

    /// On screen: not minimised, and not covered by other windows.
    private func updateVisibility() {
        guard let window else { return }
        content.isVisible = window.isSeenByUser
    }

    func windowDidChangeOcclusionState(_ notification: Notification) { updateVisibility() }
    func windowDidMiniaturize(_ notification: Notification) { updateVisibility() }
    func windowDidDeminiaturize(_ notification: Notification) { updateVisibility() }

    func windowWillClose(_ notification: Notification) {
        content.isShown = false
        content.onFinished = nil
        window = nil
        if Self.open[content.kind] === self { Self.open[content.kind] = nil }
    }
}

struct PermissionGuideWindowView: View {
    let content: any GuideContent
    let close: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            content.makeView()
            Button(action: close) {
                Text(content.isResolved ? "Done" : "Close")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .frame(minWidth: 90)
            }
            .buttonStyle(ChromeButtonStyle(look: content.isResolved ? .prominent : .plain, radius: 12))
            .help(content.closeTooltip)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 32)
        .padding(.top, 44)
        .padding(.bottom, 28)
        .frame(width: 520, height: 560)
        .background(.regularMaterial)
    }
}
