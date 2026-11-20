import Foundation

/// The folder Save writes into. Always go through `SaveLocation.folder`.
///
/// The folder chosen in Settings, else `~/Downloads`. Test mode uses `<root>/save` until a
/// folder is chosen.
enum SaveLocation {
    static var folder: URL {
        if let chosen = GeneralSettings.saveLocation { return chosen }
        if let url = TestMode.folder("save") { return url }
        return defaultFolder
    }

    /// `~/Downloads`, where Save writes until the user chooses another folder.
    static var defaultFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
}
