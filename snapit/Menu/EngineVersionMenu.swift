import Foundation

/// Shows the engine's version, read once through the C ABI.
struct EngineVersionMenu: MenuSection {
    private static let title: String = {
        let version = (try? Engine.version()) ?? "unavailable"
        return "Engine \(version)"
    }()

    var entries: [MenuEntry] {
        [.info(id: "engine.version", Self.title), .separator(id: "engine.separator")]
    }
}
