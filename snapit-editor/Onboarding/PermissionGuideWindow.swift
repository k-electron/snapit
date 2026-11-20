import AppKit
import SwiftUI

/// A Permission guide in a window of its own: after an update that took Screen Recording away, and
/// whenever a permission later goes missing. One window for the helper, like Settings: asking for a
/// guide while it is open brings it forward and looks at the permission again.
@MainActor
final class PermissionGuideWindow: NSObject, NSWindowDelegate {
    static var shared: PermissionGuideWindow?

    let model: PermissionGuideModel
    private(set) var window: NSWindow?

    private init(kind: PermissionGuideKind) {
        model = PermissionGuideModel(kind: kind)
        super.init()
    }

    static func show(_ kind: PermissionGuideKind) {
        let guide = shared ?? PermissionGuideWindow(kind: kind)
        shared = guide
        guide.present()
    }

    private func present() {
        if let window {
            HelperLifecycle.windowWillShow()
            window.makeKeyAndOrderFront(nil)
            HelperLifecycle.windowDidShow()
            model.windowResigned()
            Task { await model.windowBecameActive() }
            return
        }
        let hosting = NSHostingView(
            rootView: PermissionGuideWindowView(model: model, close: { [weak self] in self?.window?.close() }))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 520, height: 560)),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Screen Recording"
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
        model.isShown = true
        model.isVisible = window.isVisible
        Task { await model.windowBecameActive() }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        Task { await model.windowBecameActive() }
    }

    func windowDidResignKey(_ notification: Notification) {
        model.windowResigned()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        model.isVisible = window?.occlusionState.contains(.visible) ?? false
    }

    func windowWillClose(_ notification: Notification) {
        model.isShown = false
        window = nil
        if PermissionGuideWindow.shared === self { PermissionGuideWindow.shared = nil }
    }
}

struct PermissionGuideWindowView: View {
    let model: PermissionGuideModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            PermissionGuideView(model: model)
            Button(action: close) {
                Text(model.isGranted ? "Done" : "Close")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .frame(minWidth: 90)
            }
            .buttonStyle(ChromeButtonStyle(look: model.isGranted ? .prominent : .plain, radius: 12))
            .help(model.isGranted ? "Close this window" : "Close this window; snapit cannot take Captures until Screen Recording is on")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 32)
        .padding(.top, 44)
        .padding(.bottom, 28)
        .frame(width: 520, height: 560)
        .background(.regularMaterial)
    }
}
