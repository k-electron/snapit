import CoreGraphics

/// What an Action bar item can ask of the overlay it sits in.
@MainActor
protocol ActionBarHost: AnyObject {
    /// The Area now selected, in whole device pixels. Nil when there is none.
    var selectedArea: AreaSelection? { get }
    /// Ends the overlay.
    func finish(with outcome: AreaOverlayOutcome)
    /// Opens the Color picker over the Area now selected.
    func beginPickingColor()
}

/// What a control needs to build its layers.
struct ActionBarContext {
    let host: any ActionBarHost
    /// The display's pixels per point, for text layers.
    let scale: CGFloat
}

/// One control of the Action bar. An item is one file (`CaptureActionBarItem` shows the shape) and
/// one line in `ActionBarRegistry`; nothing else lists the bar's controls. The bar lays the items
/// out left to right by `order`, the key monitor runs an item's `keyEquivalent`, and the scripted
/// run reads `id`, `title` and `tooltip` back.
///
/// The bar is drawn in the overlay's layers, never in AppKit controls or SwiftUI (they cost
/// memory that never comes back). The standard item is a button: `title`, an optional `glyph` and a
/// `look`. An item with another control (a slider) overrides `makeControl` and returns an
/// `ActionBarControl` subclass with its own layers and pointer hooks.
@MainActor
protocol ActionBarItem {
    var id: String { get }
    var order: Int { get }
    /// The label on the button.
    var title: String { get }
    /// A symbol drawn before the title, in a 14 x 14 box with its origin at the bottom left.
    var glyph: CGPath? { get }
    var look: ActionBarButtonControl.Look { get }
    /// The hover tooltip, drawn in the overlay.
    var tooltip: String { get }
    /// A key (as `NSEvent.charactersIgnoringModifiers`, lowercase) that runs the item while the
    /// Action bar shows. Nil for none.
    var keyEquivalent: String? { get }
    /// What the button does (and what its key does).
    func perform(on host: any ActionBarHost)
    func makeControl(context: ActionBarContext) -> ActionBarControl
}

extension ActionBarItem {
    var glyph: CGPath? { nil }
    var look: ActionBarButtonControl.Look { .plain }
    var keyEquivalent: String? { nil }

    func makeControl(context: ActionBarContext) -> ActionBarControl {
        ActionBarButtonControl(item: self, context: context)
    }
}
