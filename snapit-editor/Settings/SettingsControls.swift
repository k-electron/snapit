import Foundation

/// The sections of the Settings page, top to bottom.
enum SettingsSection: String, CaseIterable {
    case general = "General"
    case capturing = "Capturing"
    case editor = "Editor"
    case shortcuts = "Shortcuts"
    case export = "Export"
    case about = "About"
}

/// One control of Settings: its id, what it is called and its hover tooltip. The window draws
/// from these and the scripted run reads them back, so the words are written once.
struct SettingsControl {
    let id: String
    let section: SettingsSection
    let title: String
    let tooltip: String
}

extension SettingsControl {
    static let openAtLogin = SettingsControl(
        id: "open-at-login", section: .general, title: "Open at Login",
        tooltip: "Start snapit when you log in")
    static let saveLocation = SettingsControl(
        id: "save-location", section: .general, title: "Save location",
        tooltip: "The folder Save writes into")
    static let chooseSaveLocation = SettingsControl(
        id: "save-location-choose", section: .general, title: "Choose…",
        tooltip: "Choose the folder Save writes into")
    static let afterSelectingArea = SettingsControl(
        id: "after-selecting-area", section: .capturing, title: "After selecting an Area",
        tooltip: "What happens when you let go of the mouse after selecting an Area")
    static let closeAfterCopy = SettingsControl(
        id: "close-editor-after-copy", section: .editor, title: "Close the Editor after Copy",
        tooltip: "Close the Editor once the Capture is copied")
    static let closeAfterSave = SettingsControl(
        id: "close-editor-after-save", section: .editor, title: "Close the Editor after Save",
        tooltip: "Close the Editor once the Capture is saved")
    static let openScreenshotShortcuts = SettingsControl(
        id: "open-screenshot-shortcuts", section: .shortcuts, title: "Open Keyboard Shortcuts in System Settings…",
        tooltip: "Open System Settings, then Keyboard Shortcuts… › Screenshots, to free ⌘⇧3, ⌘⇧4 and ⌘⇧5")
    static let standardResolution = SettingsControl(
        id: "export-standard-resolution", section: .export, title: "Export at standard resolution (1x)",
        tooltip: "Export a Retina Capture at its standard (1x) pixel size")

    /// The recorder for one Shortcut.
    static func shortcut(_ entry: ShortcutCatalog.Entry) -> SettingsControl {
        SettingsControl(
            id: "shortcut.\(entry.shortcut.id)", section: .shortcuts, title: entry.title,
            tooltip: "Click, then press the keys for the \(entry.title) Shortcut. Delete clears it, Esc cancels")
    }

    static let clearShortcutTooltip = "Remove this Shortcut"
}

extension AfterSelectingArea {
    var settingsTitle: String {
        switch self {
        case .showActionBar: "Show Action bar"
        case .captureOnRelease: "Capture on release"
        }
    }

    var settingsTooltip: String {
        switch self {
        case .showActionBar: "Keep the Area on screen with the Action bar, so you can adjust it before the Capture"
        case .captureOnRelease: "Take the Capture the moment you let go of the mouse"
        }
    }
}
