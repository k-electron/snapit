/// Every control of the Action bar. One entry per line, with a trailing comma; position comes
/// from each item's `order`, never from the line order, so two tickets adding an item touch
/// different files and a one-line conflict here keeps both sides.
@MainActor
enum ActionBarRegistry {
    static let all: [any ActionBarItem] = [
        CaptureActionBarItem(),
        CancelActionBarItem(),
    ].sorted { $0.order < $1.order }

    static func item(id: String) -> (any ActionBarItem)? {
        all.first { $0.id == id }
    }

    /// The item a key runs while the Action bar shows (`characters` as
    /// `charactersIgnoringModifiers`).
    static func item(forKey characters: String?) -> (any ActionBarItem)? {
        guard let key = characters?.lowercased(), !key.isEmpty else { return nil }
        return all.first { $0.keyEquivalent == key }
    }
}
