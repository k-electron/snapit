import AppKit

/// Liquid Glass behind the Action bar: a regular `NSGlassEffectView` capsule over what is below it
/// in the window (the dimmed frozen frame). It draws no controls and takes no clicks; the tiles
/// are layers above it and the overlay's controller hit-tests them.
final class ActionBarBackdropView: NSGlassEffectView {
    init() {
        super.init(frame: .zero)
        style = .regular
        appearance = NSAppearance(named: .darkAqua)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The capsule: half the bar's height.
    func setCapsule(height: CGFloat) {
        cornerRadius = height / 2
    }
}

/// The layer-hosting view that shows the Action bar's layers above its backdrop. It takes no
/// clicks either; the overlay's view does, and its controller finds the tile.
final class ActionBarTileView: NSView {
    init(bar: ActionBar) {
        super.init(frame: CGRect(origin: .zero, size: bar.size))
        layer = bar.layer  // layer-hosting: assign the layer first, then ask for layers
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
