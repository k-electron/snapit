import SwiftUI

/// Where in the Editor's top toolbar an item sits. Each slot is a glass pill.
enum ToolbarSlot: String, CaseIterable {
    /// Top left: Annotation color, width and the other options of the active tool.
    case options
    /// Top right, first pill: Undo, Redo, Delete Annotation.
    case history
    /// Top right, second pill: the drag-out thumbnail, Copy, Save.
    case export
    /// The far right, in a pill that refuses the first click on a background Editor, so that
    /// click only brings the window forward: Delete Capture.
    case destructive
}

/// One control in the Editor's top toolbar. A feature adds a file with its item and one line
/// in `ToolbarRegistry`; nothing else changes.
///
/// Most items are plain buttons: give it an `id`, a `slot`, an `order`, a `symbol`, a
/// `tooltip` and `perform`. `makeView` makes a button with the full-size hit area and the
/// hover tooltip every control has; an item that needs another control (swatches, a
/// thumbnail well) returns its own view and applies `.help` to it.
@MainActor
protocol EditorToolbarItem {
    /// Stable name. The scripted run presses the item with `editor-press <N> <id>`.
    var id: String { get }
    var slot: ToolbarSlot { get }
    /// Position inside the slot, lowest first.
    var order: Int { get }
    /// SF Symbol name.
    var symbol: String { get }
    /// Text beside the symbol; nil for a symbol-only button.
    var title: String? { get }
    /// The hover tooltip: the name and the key equivalent.
    var tooltip: String { get }
    var look: ChromeButtonStyle.Look { get }
    func isEnabled(in session: EditorSession) -> Bool
    func perform(in session: EditorSession)
    func makeView(session: EditorSession) -> AnyView
}

extension EditorToolbarItem {
    var title: String? { nil }
    var look: ChromeButtonStyle.Look { .plain }
    func isEnabled(in session: EditorSession) -> Bool { true }
    func makeView(session: EditorSession) -> AnyView {
        AnyView(ToolbarButton(item: self, session: session))
    }
}

/// The standard toolbar button: a full-size hit area and a hover tooltip.
struct ToolbarButton: View {
    let item: any EditorToolbarItem
    let session: EditorSession

    var body: some View {
        Button {
            item.perform(in: session)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.symbol).font(.system(size: 14, weight: .medium))
                if let title = item.title { Text(title).font(.system(size: 13, weight: .medium)) }
            }
            .padding(.horizontal, item.title == nil ? 0 : 12)
            .frame(minWidth: 34, minHeight: 34)
        }
        .buttonStyle(ChromeButtonStyle(look: item.look))
        .disabled(!item.isEnabled(in: session))
        .help(item.tooltip)
    }
}
