import AppKit
import QuartzCore

/// The content view of one display's panel. The scene view (layer-hosting) fills it. The Action
/// bar sits above it as two small views: Liquid Glass (`ActionBarBackdropView`) and a layer-hosting view
/// of the bar's tiles (`ActionBarTileView`). Neither takes a click: the container hands every
/// event to the scene view, whose controller hit-tests the tiles.
///
/// The container draws nothing itself: `wantsUpdateLayer` keeps AppKit from giving a full-screen
/// view a backing store.
final class AreaOverlayContainerView: NSView {
    let sceneView: AreaOverlayView
    private(set) var actionBar: ActionBar?
    private var backdrop: ActionBarBackdropView?
    private var tiles: ActionBarTileView?
    /// The bar's frame in display points while it shows.
    private(set) var actionBarFrame: CGRect?

    init(frame: NSRect, sceneView: AreaOverlayView) {
        self.sceneView = sceneView
        super.init(frame: frame)
        sceneView.frame = bounds
        addSubview(sceneView)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Top-left origin, like the overlay's own space.
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? sceneView : nil
    }

    /// Shows the Action bar for `Area` (display points) and returns its frame. The bar's
    /// layers are made the first time and kept until `releaseActionBar()`.
    @discardableResult
    func showActionBar(for area: CGRect, host: any ActionBarHost, scale: CGFloat) -> CGRect {
        let bar = actionBar ?? makeBar(host: host, scale: scale)
        let frame = ActionBarPlacement.frame(size: bar.size, area: area, in: bounds)
        if frame != actionBarFrame || backdrop?.isHidden == true {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            backdrop?.frame = frame
            tiles?.frame = frame
            backdrop?.isHidden = false
            tiles?.isHidden = false
            CATransaction.commit()
        }
        actionBarFrame = frame
        return frame
    }

    func hideActionBar() {
        guard actionBarFrame != nil else { return }
        actionBarFrame = nil
        backdrop?.isHidden = true
        tiles?.isHidden = true
    }

    func releaseActionBar() {
        backdrop?.removeFromSuperview()
        tiles?.removeFromSuperview()
        backdrop = nil
        tiles = nil
        actionBar = nil
        actionBarFrame = nil
    }

    private func makeBar(host: any ActionBarHost, scale: CGFloat) -> ActionBar {
        let bar = ActionBar(host: host, scale: scale)
        let backdrop = ActionBarBackdropView()
        backdrop.setCapsule(height: bar.size.height)
        backdrop.frame.size = bar.size
        let tiles = ActionBarTileView(bar: bar)
        addSubview(backdrop)
        addSubview(tiles)
        self.actionBar = bar
        self.backdrop = backdrop
        self.tiles = tiles
        return bar
    }
}
