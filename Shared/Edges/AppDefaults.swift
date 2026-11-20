import Foundation

/// snapit's `UserDefaults`, shared by both processes. Always go through `AppDefaults.store`,
/// never `UserDefaults.standard`: in the Editor helper that is the helper's own domain, so the
/// two processes would see different values.
///
/// Normal runs use the menu bar app's bundle ID domain in both processes. Test mode keeps the
/// values in a plist inside the run's root, read and written straight through
/// (`FileBackedDefaults`), so that domain in `~/Library/Preferences` is never read or written and
/// the two processes see each other's writes at once, as they do through the real domain.
enum AppDefaults {
    static let store: UserDefaults = {
        if let root = TestMode.root {
            guard let store = FileBackedDefaults(file: root.appendingPathComponent("defaults.plist")) else {
                fatalError("snapit: test mode could not make its defaults store")
            }
            return store
        }
        if Bundle.main.bundleIdentifier == AppIdentity.mainBundleIdentifier { return .standard }
        return UserDefaults(suiteName: AppIdentity.mainBundleIdentifier) ?? .standard
    }()
}
