import AppKit

/// When the helper is an agent and when it is a regular app. It starts as an agent: no Dock
/// icon, no Cmd-Tab entry. While a window shows it is a regular app, with a Dock icon, a
/// Cmd-Tab entry and its own menus. It quits when its last window closes.
///
/// Any window the helper hosts (Editor, and later Settings, Onboarding and the guides) calls
/// `windowWillShow()` before it shows its window and `windowDidShow()` after it is on screen.
@MainActor
enum HelperLifecycle {
    /// True once any window has shown. Until then the helper (warm, or started on its own)
    /// must not quit just because it has no window.
    private(set) static var hasShownWindow = false
    /// True when one of the helper's windows has shown since its last window closed: a helper that is
    /// quitting because it has no windows stays for it (`HelperDelegate.applicationShouldTerminate`).
    static var windowShownSinceLastClose = false

    static func windowWillShow() {
        // Become a regular app before the window shows, so it appears once, already owned by
        // a regular app.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    static func windowDidShow() {
        hasShownWindow = true
        windowShownSinceLastClose = true
        // Re-assign the main menu so the menu bar refreshes after the policy switch.
        NSApp.mainMenu = NSApp.mainMenu
        activate()
    }

    /// Makes the helper the active app. The menu bar app also asks LaunchServices to bring the
    /// helper forward when it opens a Capture (`EditorActivation`), because macOS lets an app
    /// that is not frontmost refuse to be activated by another. A scripted run never takes
    /// focus from what the user is doing.
    static func activate() {
        if !TestMode.isActive { NSApp.activate() }
    }
}
