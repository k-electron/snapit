import ServiceManagement

/// Whether snapit opens at login: `SMAppService.mainApp`. Always go through `LoginItem.current`;
/// a scripted run swaps in `FakeLoginItem` and never touches the real login items.
///
/// The status is read when Settings opens (the helper asks over the socket), never polled.
@MainActor
protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

@MainActor
struct SMAppLoginItem: LoginItemService {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        default: .notRegistered
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// Test mode's login item: a status kept in the run's defaults, so it survives a relaunch as the
/// real one does, starting where a fresh install starts (`notFound`).
@MainActor
final class FakeLoginItem: LoginItemService {
    static let shared = FakeLoginItem()
    private static let key = "test.loginItemStatus"

    private(set) var status: LoginItemStatus {
        get { AppDefaults.store.string(forKey: Self.key).flatMap(LoginItemStatus.init(rawValue:)) ?? .notFound }
        set { AppDefaults.store.set(newValue.rawValue, forKey: Self.key) }
    }

    func register() throws { status = .enabled }
    func unregister() throws { status = .notRegistered }

    /// What the user doing it in System Settings would do (test mode only).
    func simulate(_ status: LoginItemStatus) { self.status = status }
}

@MainActor
enum LoginItem {
    static let current: any LoginItemService = TestMode.isActive ? FakeLoginItem.shared : SMAppLoginItem()
}
