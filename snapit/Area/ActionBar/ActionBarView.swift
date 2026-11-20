import AppKit
import SwiftUI

/// The Action bar: every item of `ActionBarRegistry` on one glass capsule.
struct ActionBarView: View {
    let host: any ActionBarHost
    /// Tells the overlay where an item ended up, in the bar's own space (for the scripted run).
    let report: (String, CGRect) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(ActionBarRegistry.all, id: \.id) { item in
                    item.makeView(host: host)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
                            report(item.id, $0)
                        }
                }
            }
            .padding(6)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(10)  // room for the glass shadow inside the hosting view
        .contentShape(Rectangle())  // a click on the padding is the bar's, never a new selection
        .coordinateSpace(.named(Self.space))
        .environment(\.colorScheme, .dark)
    }

    private nonisolated static let space = "actionBar"
}

/// The hosting view of the Action bar. A click on it is the user's first click on the overlay
/// panel, so it must act at once.
final class ActionBarHostingView: NSHostingView<ActionBarView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
