import AppKit

/// Every control in the Editor's top toolbar. A feature adds its item to `all` with one line
/// (a line each, with a trailing comma, so two additions are a one-line merge conflict that
/// keeps both sides). Position comes from each item's `slot` and `order`, so the line order
/// here never matters.
@MainActor
enum ToolbarRegistry {
    static let all: [any EditorToolbarItem] = [
        ApplyCropToolbarItem(),
        CancelCropToolbarItem(),
        CloseToolbarItem(),
        ColorSwatchesToolbarItem(),
        ColorWheelToolbarItem(),
        CopyToolbarItem(),
        DeleteAnnotationToolbarItem(),
        DeleteCaptureToolbarItem(),
        EyedropperToolbarItem(),
        DragOutToolbarItem(),
        SaveToolbarItem(),
        RedoToolbarItem(),
        AnnotationFillToolbarItem(),
        UndoToolbarItem(),
        SizeToolbarItem(),
    ]

    /// The items of one slot, in order.
    static func items(in slot: ToolbarSlot) -> [any EditorToolbarItem] {
        all.filter { $0.slot == slot }.sorted { $0.order < $1.order }
    }

    /// The items listed in one of the helper's menus, in order.
    static func items(in menu: EditorMenu) -> [any EditorToolbarItem] {
        all.filter { $0.menu == menu }.sorted { $0.order < $1.order }
    }

    static func item(id: String) -> (any EditorToolbarItem)? {
        all.first { $0.id == id }
    }

    /// The item whose key equivalent this key press is.
    static func item(matching event: NSEvent) -> (any EditorToolbarItem)? {
        all.first { $0.keyEquivalent?.matches(event) == true }
    }
}
