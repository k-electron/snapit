import AppKit

/// The blur behind the Action bar: a dark HUD material over what is below it in the window (the
/// dimmed frozen frame). It draws no controls and takes no clicks. A glass look can replace it by
/// making this an `NSGlassEffectView` (set its `cornerRadius`, drop `material`); that costs about
/// 2 MB more, once, so the bar uses the material.
final class ActionBarBackdropView: NSVisualEffectView {
    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The capsule: half the bar's height.
    func setCapsule(height: CGFloat) {
        layer?.cornerRadius = height / 2
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
