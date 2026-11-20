import AppKit

/// When the helper is an agent and when it is a regular app. It starts as an agent: no Dock
/// icon, no Cmd-Tab entry. While a window shows it is a regular app, with a Dock icon, a
/// Cmd-Tab entry and its own menus. It quits when its last window closes.
///
/// Any window the helper hosts (Editor, and later Settings, Onboarding and the guides) calls
/// `windowWillShow()` before it creates its window and `windowDidShow()` after it is on screen.
@MainActor
enum HelperLifecycle {
    /// True once any window has shown. Until then the helper (warm, or started on its own)
    /// must not quit just because it has no window.
    private(set) static var hasShownWindow = false

    static func windowWillShow() {
        // Become a regular app before the window exists, so it appears once, already owned by
        // a regular app.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    static func windowDidShow() {
        hasShownWindow = true
        // Re-assign the main menu so the menu bar refreshes after the policy switch.
        NSApp.mainMenu = NSApp.mainMenu
        // A scripted run must never take focus from what the user is doing.
        if !TestMode.isActive { NSApp.activate() }
    }
}
