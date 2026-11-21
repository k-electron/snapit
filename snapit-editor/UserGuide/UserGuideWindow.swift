import AppKit
import SwiftUI

/// The User Guide window. One window for the whole helper: asking for it while it is open brings it
/// forward. It is a helper window like Settings: it goes through `HelperLifecycle`, and the helper
/// quits when it closes (unless another window is open). The guide is read from the bundle when
/// the window opens and released when it closes.
@MainActor
final class UserGuideWindow: NSObject, NSWindowDelegate {
    static var shared: UserGuideWindow?
    /// Test mode only: a guide the next window shows instead of the bundled one (`user-guide-fixture`).
    static var fixture: GuideDocument?

    let model = UserGuideModel(document: fixture ?? .bundled())
    private(set) var window: NSWindow?

    /// Shows the User Guide, or brings the open window forward.
    static func show() {
        let guide = shared ?? UserGuideWindow()
        shared = guide
        guide.present()
    }

    private func present() {
        if let window {
            HelperLifecycle.windowWillShow()
            window.makeKeyAndOrderFront(nil)
            HelperLifecycle.windowDidShow()
            return
        }
        let controller = NSHostingController(rootView: UserGuideView(model: model))
        controller.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 920, height: 640)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.contentViewController = controller
        window.title = model.windowTitle
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 920, height: 640))
        window.center()
        self.window = window

        HelperLifecycle.windowWillShow()
        window.makeKeyAndOrderFront(nil)
        HelperLifecycle.windowDidShow()
        // The search field would take the keyboard when the window opens, and its blinking caret
        // keeps the helper busy. The window itself holds it until a click puts it in the field.
        window.makeFirstResponder(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
        if UserGuideWindow.shared === self { UserGuideWindow.shared = nil }
    }
}
