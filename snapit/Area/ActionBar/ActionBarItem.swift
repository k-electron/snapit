import SwiftUI

/// What an Action bar item can ask of the overlay it sits in.
@MainActor
protocol ActionBarHost: AnyObject {
    /// The Area now selected, in whole device pixels. Nil when there is none.
    var selectedArea: AreaSelection? { get }
    /// Ends the overlay.
    func finish(with outcome: AreaOverlayOutcome)
}

/// One control of the Action bar. An item is one file (`CaptureActionBarItem` shows the shape)
/// and one line in `ActionBarRegistry`; nothing else lists the bar's controls. The bar lays the
/// items out left to right by `order`, the key monitor runs an item's `keyEquivalent`, and the
/// scripted run reads `id`, `title` and `tooltip` back.
///
/// The standard item is a glass button (`title`, `symbol`, `look`). An item with a different
/// control (a slider, say) overrides `makeView`; it still gives `title` and `tooltip` and puts a
/// full-size hit area and a `.help(tooltip)` on every button it draws.
@MainActor
protocol ActionBarItem {
    var id: String { get }
    var order: Int { get }
    /// The label on the button.
    var title: String { get }
    /// An SF Symbol shown before the title.
    var symbol: String? { get }
    var look: ActionBarButtonStyle.Look { get }
    /// The hover tooltip.
    var tooltip: String { get }
    /// A key (as `NSEvent.charactersIgnoringModifiers`, lowercase) that runs the item while the
    /// Action bar shows. Nil for none.
    var keyEquivalent: String? { get }
    /// What the button does.
    func perform(on host: any ActionBarHost)
    func makeView(host: any ActionBarHost) -> AnyView
}

extension ActionBarItem {
    var symbol: String? { nil }
    var look: ActionBarButtonStyle.Look { .plain }
    var keyEquivalent: String? { nil }

    func makeView(host: any ActionBarHost) -> AnyView {
        AnyView(
            Button {
                perform(on: host)
            } label: {
                HStack(spacing: 6) {
                    if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)) }
                    Text(title).font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 14)
                .frame(minWidth: 84, minHeight: 34)
            }
            .buttonStyle(ActionBarButtonStyle(look: look))
            .help(tooltip))
    }
}
