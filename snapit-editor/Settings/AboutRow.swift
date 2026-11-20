import Foundation

/// One row of Settings' About section. A row is its own file (`VersionAboutRow.swift` shows the
/// shape: an extension of `SettingsControl` with its id, title and tooltip, and the row) and one
/// line in `AboutRows.all`. The window and the scripted run's `settings-facts` both draw from the
/// list, so nothing else changes.
struct AboutRow {
    enum Content {
        /// A line of text beside the title.
        case text(@MainActor () -> String)
        /// A button with the title as its label.
        case button(@MainActor (SettingsModel) -> Void)
    }

    let control: SettingsControl
    let content: Content
}

enum AboutRows {
    static let all: [AboutRow] = [
        .version,
        .checkForUpdates,
    ]
}
