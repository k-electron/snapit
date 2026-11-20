import Foundation

/// The version snapit is running: the bundle's `CFBundleShortVersionString`. A scripted run may
/// pretend another one (`update-installed-version`).
@MainActor
enum InstalledVersion {
    /// Test mode only.
    static var pretended: String?

    static var string: String {
        pretended ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    }
}
