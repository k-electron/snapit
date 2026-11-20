import Foundation

/// A setting stored through `AppDefaults.store`, the same in both processes. The Settings
/// window writes these keys; every reader falls back to the default the spec gives.
///
/// A feature with its own settings adds its own file with an `enum …Settings` beside this
/// one and reads through `AppSetting`.
enum AppSetting {
    /// The Bool stored under `key`, or `defaultValue` when none is stored. A string such as
    /// "true" or "false" counts too, which is how the scripted run writes defaults.
    static func bool(_ key: String, default defaultValue: Bool) -> Bool {
        let value = AppDefaults.store.object(forKey: key)
        if let flag = value as? Bool { return flag }
        if let text = (value as? String)?.lowercased() {
            switch text {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: break
            }
        }
        return defaultValue
    }
}

/// The Editor section of Settings.
enum EditorSettings {
    static let closeAfterCopyKey = "closeEditorAfterCopy"
    static let closeAfterSaveKey = "closeEditorAfterSave"

    /// Close the Editor after Copy. On by default.
    static var closeAfterCopy: Bool { AppSetting.bool(closeAfterCopyKey, default: true) }
    /// Close the Editor after Save. On by default.
    static var closeAfterSave: Bool { AppSetting.bool(closeAfterSaveKey, default: true) }
}
