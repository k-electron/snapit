import Foundation

/// snapit's `UserDefaults`, shared by both processes. Always go through `AppDefaults.store`,
/// never `UserDefaults.standard`: in the Editor helper that is the helper's own domain, so the
/// two processes would see different values.
///
/// Normal runs use the menu bar app's bundle ID domain in both processes. Test mode keeps the
/// values in a plist inside the run's root (a suite named by an absolute path), so that domain
/// in `~/Library/Preferences` is never read or written.
enum AppDefaults {
    static let store: UserDefaults = {
        if let root = TestMode.root {
            let path = root.appendingPathComponent("defaults").path
            return UserDefaults(suiteName: path) ?? UserDefaults()
        }
        if Bundle.main.bundleIdentifier == AppIdentity.mainBundleIdentifier { return .standard }
        return UserDefaults(suiteName: AppIdentity.mainBundleIdentifier) ?? .standard
    }()
}
