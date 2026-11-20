import Foundation

/// The General section of Settings (Open at Login lives in the menu bar app, behind
/// `LoginItem`).
enum GeneralSettings {
    static let saveLocationKey = "saveLocation"

    /// The folder the user chose for Save, or nil while Save uses `~/Downloads`.
    static var saveLocation: URL? {
        guard let path = AppDefaults.store.string(forKey: saveLocationKey), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
