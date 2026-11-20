import AppKit
import SwiftUI

/// The target of "Settings…" (⌘,) in the helper's own app menu.
@MainActor
final class SettingsMenuTarget: NSObject {
    static let shared = SettingsMenuTarget()

    @objc func showSettings(_ sender: Any?) {
        SettingsWindow.show()
    }
}

/// The Settings window. One window for the whole helper: asking for Settings while it is open
/// brings it forward. It is a helper window like the Editor: it goes through `HelperLifecycle`,
/// and the helper quits when it closes (unless an Editor is still open).
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static var shared: SettingsWindow?

    let model = SettingsModel()
    private(set) var window: NSWindow?

    /// Shows Settings, or brings the open window forward. Either way the Open at Login status
    /// is read again: that read, when Settings opens or comes forward, is its only one.
    static func show() {
        let settings = shared ?? SettingsWindow()
        shared = settings
        settings.present()
        Task { await settings.model.refreshLogin() }
    }

    private func present() {
        if let window {
            HelperLifecycle.windowWillShow()
            window.makeKeyAndOrderFront(nil)
            HelperLifecycle.windowDidShow()
            return
        }
        let hosting = NSHostingView(rootView: SettingsView(model: model, window: { [weak self] in self?.window }))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 520, height: 640)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = hosting
        window.setContentSize(NSSize(width: 520, height: 640))
        window.center()
        self.window = window

        HelperLifecycle.windowWillShow()
        window.makeKeyAndOrderFront(nil)
        HelperLifecycle.windowDidShow()
    }

    func windowDidResignKey(_ notification: Notification) {
        model.cancelRecording()
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelRecording()
        window = nil
        if SettingsWindow.shared === self { SettingsWindow.shared = nil }
    }
}
