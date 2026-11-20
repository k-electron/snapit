import AppKit

/// The content view of one display's panel. The scene view (layer-hosting, so it cannot hold real
/// subviews) fills it; the Action bar's controls are real views and live here, beside it, in a
/// hosting view sized exactly to the bar, so a click lands on the bar only where the bar is.
///
/// The container draws nothing itself: `wantsUpdateLayer` keeps AppKit from giving a full-screen
/// view a backing store.
final class AreaOverlayContainerView: NSView {
    let sceneView: AreaOverlayView
    private var bar: ActionBarHostingView?
    /// Where each item of the bar is, in the bar's own space (top-left origin). The bar reports
    /// them after it lays out.
    private(set) var itemFrames: [String: CGRect] = [:]

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

    /// The bar's frame in display points, nil when it is not showing.
    var actionBarFrame: CGRect? {
        guard let bar, !bar.isHidden else { return nil }
        return bar.frame
    }

    /// Shows the Action bar for `selection` (display points) and returns its frame. The hosting
    /// view is made the first time and kept until `releaseActionBar()`.
    @discardableResult
    func showActionBar(for selection: CGRect, host: any ActionBarHost) -> CGRect {
        let bar = bar ?? makeBar(host: host)
        let frame = ActionBarPlacement.frame(size: bar.frame.size, selection: selection, in: bounds)
        if bar.frame != frame { bar.frame = frame }
        bar.isHidden = false
        return frame
    }

    func hideActionBar() {
        bar?.isHidden = true
    }

    func releaseActionBar() {
        bar?.removeFromSuperview()
        bar = nil
        itemFrames.removeAll()
    }

    private func makeBar(host: any ActionBarHost) -> ActionBarHostingView {
        let view = ActionBarHostingView(
            rootView: ActionBarView(host: host) { [weak self] id, frame in self?.itemFrames[id] = frame })
        view.layoutSubtreeIfNeeded()
        view.frame.size = view.fittingSize
        addSubview(view)
        bar = view
        return view
    }
}
