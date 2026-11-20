/// Every control in the Editor's top toolbar. A feature adds its item to `all` with one line;
/// position comes from each item's `slot` and `order`, so the line order here never matters
/// and parallel tickets never conflict.
@MainActor
enum ToolbarRegistry {
    static let all: [any EditorToolbarItem] = [
        CopyToolbarItem(),
        DeleteCaptureToolbarItem(),
    ]

    /// The items of one slot, in order.
    static func items(in slot: ToolbarSlot) -> [any EditorToolbarItem] {
        all.filter { $0.slot == slot }.sorted { $0.order < $1.order }
    }

    static func item(id: String) -> (any EditorToolbarItem)? {
        all.first { $0.id == id }
    }
}
