import Foundation

extension SettingsControl {
    static let checkForUpdates = SettingsControl(
        id: "check-for-updates", section: .about, title: "Check for Updates…",
        tooltip: "Ask GitHub whether a newer snapit is out. This is the only time snapit goes online")
}

extension AboutRow {
    /// Opens the update window, which asks the menu bar app to check: the same path as the menu's
    /// Check for Updates….
    static let checkForUpdates = AboutRow(
        control: .checkForUpdates,
        content: .button { _ in UpdateWindow.showAndCheck() })
}
