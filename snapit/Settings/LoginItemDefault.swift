import Foundation

/// Open at Login is on by default: the first launch from a normal place registers the login
/// item, once. A later Off in Settings is the user's and stays off across launches, because the
/// default is applied only while this flag is unset.
@MainActor
enum LoginItemDefault {
    static let appliedKey = "openAtLoginDefaultApplied"

    static func applyOnce() {
        guard !AppSetting.bool(appliedKey, default: false) else { return }
        AppDefaults.store.set(true, forKey: appliedKey)
        do {
            try LoginItem.current.register()
        } catch {
            NSLog("snapit: could not register the login item: \(error)")
        }
    }
}
