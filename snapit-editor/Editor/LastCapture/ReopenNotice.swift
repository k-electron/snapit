import AppKit
import SwiftUI

/// "That Capture couldn't be reopened.": what Reopen Last Capture shows when the stored Capture
/// is damaged, so it never does nothing. A helper window like the Editor: it goes through
/// `HelperLifecycle`, and the helper quits when it closes (when nothing else is open).
@MainActor
final class ReopenNotice: NSObject, NSWindowDelegate {
    static let message = "That Capture couldn't be reopened."

    private static var shared: ReopenNotice?
    /// The notice on screen, or nil.
    static var current: ReopenNotice? { shared }

    private(set) var window: NSWindow?

    static func show() {
        if let shared, let window = shared.window {
            window.makeKeyAndOrderFront(nil)
            HelperLifecycle.activate()
            return
        }
        let notice = ReopenNotice()
        shared = notice
        notice.present()
    }

    func close() { window?.close() }

    private func present() {
        let hosting = NSHostingView(rootView: ReopenNoticeView(onClose: { [weak self] in self?.close() }))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 380, height: 160)),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.center()
        self.window = window

        HelperLifecycle.windowWillShow()
        window.makeKeyAndOrderFront(nil)
        HelperLifecycle.windowDidShow()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        if ReopenNotice.shared === self { ReopenNotice.shared = nil }
    }
}

private struct ReopenNoticeView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(ReopenNotice.message)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onClose) {
                Text("OK")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(minWidth: 120)
            }
            .buttonStyle(ChromeButtonStyle(look: .prominent, radius: 12))
            .help("Close this message")
            .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 380)
        .background(.regularMaterial)
    }
}
