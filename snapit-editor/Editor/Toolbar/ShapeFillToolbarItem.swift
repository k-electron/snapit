import SwiftUI

/// Outline or solid fill, for Rectangle and Oval: two buttons side by side, the chosen one lit.
/// It applies to the selected Rectangle or Oval and to the ones drawn next, and is remembered
/// across launches. Both are plain buttons (the whole tile is the hit area, the first click on
/// a background Editor works, each has its tooltip).
struct ShapeFillToolbarItem: EditorToolbarItem {
    let id = "annotation-fill"
    let slot = ToolbarSlot.options
    let order = 300
    let symbol = "rectangle"
    let tooltip = "Fill: Outline or Solid"

    func isEnabled(in session: EditorSession) -> Bool { session.fillApplies }
    func isVisible(in session: EditorSession) -> Bool { !session.isCropping }

    /// Pressing the item switches between the two.
    func perform(in session: EditorSession) {
        session.setAnnotationFilled(!session.fillIsSolid)
    }

    func makeView(session: EditorSession) -> AnyView {
        AnyView(ShapeFillControl(session: session))
    }
}

private struct ShapeFillControl: View {
    let session: EditorSession

    var body: some View {
        let isSolid = session.fillIsSolid
        HStack(spacing: 2) {
            choice(symbol: "rectangle", tooltip: "Outline", chosen: !isSolid, filled: false)
            choice(symbol: "rectangle.fill", tooltip: "Solid fill", chosen: isSolid, filled: true)
        }
        .disabled(!session.fillApplies)
    }

    private func choice(symbol: String, tooltip: String, chosen: Bool, filled: Bool) -> some View {
        Button {
            session.setAnnotationFilled(filled)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(minWidth: 34, minHeight: 34)
        }
        .buttonStyle(ChromeButtonStyle(look: chosen ? .selected : .plain))
        .help(tooltip)
        .controlMarker(tooltip)
    }
}
