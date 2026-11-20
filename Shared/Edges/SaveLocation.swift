import Foundation

/// The folder Save writes into. Always go through `SaveLocation.folder`.
///
/// Normal runs use `~/Downloads` until Settings lets the user choose another folder. Test
/// mode uses `<root>/save`.
enum SaveLocation {
    static var folder: URL {
        if let url = TestMode.folder("save") { return url }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
}
