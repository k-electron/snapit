import AppKit
import SwiftUI

/// The Onboarding window. One window for the whole helper: asking for Onboarding while it is open
/// brings it forward. It is a helper window like the Editor: it goes through `HelperLifecycle`, and
/// the helper quits when it closes (unless an Editor is still open).
///
/// The step is stored as it changes, so closing the window at any step resumes there at the next
/// launch or Shortcut press.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    static var shared: OnboardingWindow?

    let model: OnboardingModel
    private(set) var window: NSWindow?

    private init(step: OnboardingStep) {
        model = OnboardingModel(step: step)
        super.init()
        model.closeWindow = { [weak self] in self?.window?.close() }
    }

    /// Shows Onboarding at its stored step, or brings the open window forward.
    static func show() {
        let onboarding = shared ?? OnboardingWindow(step: OnboardingProgress.resumeStep)
        shared = onboarding
        onboarding.present()
    }

    private func present() {
        if let window {
            HelperLifecycle.windowWillShow()
            window.makeKeyAndOrderFront(nil)
            HelperLifecycle.windowDidShow()
            return
        }
        let hosting = NSHostingView(rootView: OnboardingView(model: model))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 600, height: 640)),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Onboarding"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = hosting
        window.setContentSize(NSSize(width: 600, height: 640))
        window.center()
        self.window = window

        HelperLifecycle.windowWillShow()
        window.makeKeyAndOrderFront(nil)
        HelperLifecycle.windowDidShow()
        model.guide.isVisible = window.isSeenByUser
    }

    // MARK: Window events

    func windowDidBecomeKey(_ notification: Notification) {
        Task { await model.windowBecameActive() }
    }

    func windowDidResignKey(_ notification: Notification) {
        model.windowResigned()
    }

    /// On screen: not minimised, and not covered by other windows.
    private func updateVisibility() {
        guard let window else { return }
        model.guide.isVisible = window.isSeenByUser
    }

    func windowDidChangeOcclusionState(_ notification: Notification) { updateVisibility() }
    func windowDidMiniaturize(_ notification: Notification) { updateVisibility() }
    func windowDidDeminiaturize(_ notification: Notification) { updateVisibility() }

    func windowWillClose(_ notification: Notification) {
        model.settings.cancelRecording()
        model.guide.isShown = false
        window = nil
        if OnboardingWindow.shared === self { OnboardingWindow.shared = nil }
    }
}
