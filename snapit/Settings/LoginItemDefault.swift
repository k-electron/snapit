import Foundation

/// Open at Login is on by default: the first launch of a copy that lives in an Applications
/// folder registers the login item, once. A later Off in Settings is the user's and stays off
/// across launches, because the default is applied only while the flag is unset, and the flag is
/// set only after registering worked. A copy that runs from anywhere else (a disk image, a
/// translocated path, a build folder) is not the one to open at login.
@MainActor
enum LoginItemDefault {
    static let appliedKey = "openAtLoginDefaultApplied"

    /// Registers the login item when this copy is eligible and the default has not been applied.
    @discardableResult
    static func applyIfEligible(environment: any InstallEnvironment = InstallEdge.current) -> Bool {
        guard !AppSetting.bool(appliedKey, default: false), isEligible(environment: environment) else { return false }
        do {
            try LoginItem.current.register()
        } catch {
            NSLog("snapit: could not register the login item: \(error)")
            return false
        }
        switch LoginItem.current.status {
        case .enabled, .requiresApproval:
            AppDefaults.store.set(true, forKey: appliedKey)
            return true
        case .notRegistered, .notFound:
            return false
        }
    }

    /// Runs from a normal place (no move or fix pending) that is inside an Applications folder.
    static func isEligible(environment: any InstallEnvironment) -> Bool {
        guard InstallCheck.plan(environment: environment) == .stay else { return false }
        var folders = [environment.applicationsFolder]
        if !TestMode.isActive {
            folders.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true))
        }
        let bundle = RealPath.of(environment.bundlePath)
        return folders.contains { bundle.hasPrefix(RealPath.of($0.path) + "/") }
    }
}
