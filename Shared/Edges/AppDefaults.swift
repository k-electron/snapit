import Foundation

/// snapit's `UserDefaults`. Always go through `AppDefaults.store`, never
/// `UserDefaults.standard`.
///
/// Test mode keeps the values in a plist inside the run's root (a suite named by an absolute
/// path), so the bundle ID's real domain in `~/Library/Preferences` is never read or written.
enum AppDefaults {
    static let store: UserDefaults = {
        guard let root = TestMode.root else { return .standard }
        let path = root.appendingPathComponent("defaults").path
        return UserDefaults(suiteName: path) ?? .standard
    }()

    /// Where the values live, for the scripted run's isolation checks.
    static var location: String {
        TestMode.root?.appendingPathComponent("defaults.plist").path ?? "standard"
    }
}
