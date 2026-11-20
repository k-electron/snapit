import Foundation

/// Shows the engine's version, read once through the C ABI.
@MainActor
enum EngineVersionMenu {
    private static let title: String = {
        let version = (try? Engine.version()) ?? "unavailable"
        return "Engine \(version)"
    }()

    static var entries: [MenuEntry] {
        [.info(title), .separator]
    }
}
