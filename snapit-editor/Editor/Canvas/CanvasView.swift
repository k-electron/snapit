import AppKit
import QuartzCore

/// The Editor's canvas: a layer-hosting view. Core Animation layers hold everything, the view
/// has no `draw(_:)`, and nothing ever asks it to redraw. The Capture is one layer; the
/// `CGImage` it shows reads the Capture file's mapping in place, and Core Animation then keeps
/// its own copy of the pixels for the GPU (a 5K Capture makes the helper about 130 MB while the
/// Editor is open; the helper exits with the Editor).
///
/// The canvas is built empty, with its layers, and gets its Capture later with `setCapture`,
/// so a helper can build the whole window while it is still warming up.
///
/// Layers, back to front: `root` > `contentLayer` (the visible part of the Capture in points,
/// scaled to fit and centred) > `clipLayer` (clips to the visible part) > `world` (the whole
/// Capture, moved so a crop's corner is at the top left) > `imageLayer` (the Capture), then
/// `effectLayer` and `annotationLayer` (clipped to the Capture); and `selectionWorld` (the same
/// place as `world`, not clipped) > `selectionLayer` on top. `annotationLayers` keeps one layer
/// per Annotation; the effect, annotation and selection layers' geometry is flipped: positions
/// are image points, origin at the top left, the same coordinates a tool receives from the
/// pointer, whether or not a crop is applied.
@MainActor
final class CanvasView: NSView {
    /// The visible part of the Capture in points (all of it, or what an applied crop keeps),
    /// scaled to fit the view.
    let contentLayer = CALayer()
    /// Where the layers of the kinds drawn beneath the Annotations are (Redaction: Export
    /// pixelates before it draws any Annotation), in image points, origin at the top left.
    let effectLayer = CALayer()
    /// Where the Annotations' layers are, in image points, origin at the top left.
    let annotationLayer = CALayer()
    /// The selected Annotation's outline and handles, above the Annotations and not clipped.
    let selectionLayer = CALayer()
    private(set) var annotationLayers: AnnotationLayers!
    private let root = CALayer()
    private let clipLayer = CALayer()
    private let world = CALayer()
    private let selectionWorld = CALayer()
    private let imageLayer = CALayer()
    private var pointSize = CGSize(width: 1, height: 1)
    /// The applied crop in Capture pixels; nil shows all of the Capture.
    private(set) var cropPixels: PixelRect?
    /// The crop rectangle being dragged (Crop tool), in image points.
    private var cropDraft: CGRect?
    private var cropOverlay: CropOverlayLayers!
    private var capture: PixelBuffer?
    private var captureScale = 1.0
    weak var session: EditorSession?

    /// Space kept free around the Capture.
    var padding: CGFloat = 6

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Layer-hosting: the layer is set before `wantsLayer`, so AppKit never draws into it.
        layer = root
        wantsLayer = true

        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        imageLayer.magnificationFilter = .nearest
        effectLayer.isGeometryFlipped = true
        effectLayer.masksToBounds = true
        annotationLayer.isGeometryFlipped = true
        annotationLayer.masksToBounds = true
        selectionLayer.isGeometryFlipped = true
        clipLayer.masksToBounds = true
        for layer in [world, selectionWorld] { layer.anchorPoint = .zero }
        world.addSublayer(imageLayer)
        world.addSublayer(effectLayer)
        world.addSublayer(annotationLayer)
        clipLayer.addSublayer(world)
        selectionWorld.addSublayer(selectionLayer)
        contentLayer.addSublayer(clipLayer)
        contentLayer.addSublayer(selectionWorld)
        cropOverlay = CropOverlayLayers(host: selectionLayer)
        annotationLayers = AnnotationLayers(host: annotationLayer, effectHost: effectLayer, selectionHost: selectionLayer)
        root.addSublayer(contentLayer)
    }

    required init?(coder: NSCoder) { fatalError("CanvasView is made in code") }

    /// Shows the Capture: `pointSize` is its size in points, `pixels` its read-only mapping
    /// (what a kind's preview may read) and `scale` the pixels per point.
    func setCapture(image: CGImage, pointSize: CGSize, pixels: PixelBuffer, scale: Double) {
        self.pointSize = CGSize(width: max(pointSize.width, 1), height: max(pointSize.height, 1))
        capture = pixels
        captureScale = scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let whole = CGRect(origin: .zero, size: self.pointSize)
        for layer in [world, selectionWorld] { layer.bounds = whole }
        effectLayer.frame = whole
        annotationLayer.frame = whole
        selectionLayer.frame = whole
        imageLayer.frame = whole
        placeLayers()
        imageLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        imageLayer.contents = image
        CATransaction.commit()
        needsLayout = true
    }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// The visible part of the Capture in image points: all of it, or what an applied crop keeps.
    var viewRect: CGRect {
        guard let cropPixels else { return CGRect(origin: .zero, size: pointSize) }
        return CropGeometry.points(cropPixels, scale: captureScale)
    }

    /// How many view points one Capture point takes: 1 until the visible part is bigger than the
    /// canvas, then it shrinks to fit.
    var zoom: CGFloat {
        let size = viewRect.size
        let available = CGSize(width: max(bounds.width - 2 * padding, 1), height: max(bounds.height - 2 * padding, 1))
        return min(1, available.width / size.width, available.height / size.height)
    }

    /// Shows only the part of the Capture an applied crop keeps (`nil`: all of it). Moves two
    /// layers and brings the Redaction previews up to date; nothing is redrawn.
    func setCrop(_ pixels: PixelRect?) {
        guard pixels != cropPixels else { return }
        cropPixels = pixels
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeLayers()
        CATransaction.commit()
        needsLayout = true
        annotationLayers.contextChanged(renderContext)
    }

    /// Shows the crop rectangle being dragged, with the shade outside it and its handles (`nil`:
    /// none). In image points.
    func showCropDraft(_ rect: CGRect?) {
        cropDraft = rect
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cropOverlay.show(rect, imageSize: pointSize, zoom: zoom)
        CATransaction.commit()
    }

    /// Sizes the visible window on the Capture and moves the Capture under it.
    private func placeLayers() {
        let view = viewRect
        contentLayer.bounds = CGRect(origin: .zero, size: view.size)
        clipLayer.frame = contentLayer.bounds
        // The world layers are y-up like the view, while image points count down from the top: the
        // crop's top left corner goes to the visible window's top left.
        let origin = CGPoint(x: -view.minX, y: view.height - pointSize.height + view.minY)
        for layer in [world, selectionWorld] { layer.position = origin }
    }

    override func layout() {
        super.layout()
        // Only the frame of one layer changes when the window resizes; nothing is redrawn.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = bounds
        let zoom = zoom
        contentLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        contentLayer.setAffineTransform(CGAffineTransform(scaleX: zoom, y: zoom))
        cropOverlay.show(cropDraft, imageSize: pointSize, zoom: zoom)
        CATransaction.commit()
        annotationLayers.contextChanged(renderContext)
    }

    /// What a kind's preview layer is given.
    var renderContext: AnnotationRenderContext {
        AnnotationRenderContext(capture: capture, scale: captureScale, zoom: zoom, cropPixels: cropPixels)
    }

    /// Shows the Annotations, with `selected` outlined.
    func showAnnotations(_ annotations: [Annotation], selected: Annotation?) {
        annotationLayers.show(annotations, selected: selected, context: renderContext)
    }

    /// A point in the view, as a point of the Capture (origin at its top left).
    func imagePoint(fromViewPoint point: CGPoint) -> CGPoint {
        let zoom = zoom
        let view = viewRect
        let originX = bounds.midX - view.width * zoom / 2
        let originY = bounds.midY + view.height * zoom / 2
        return CGPoint(x: (point.x - originX) / zoom + view.minX, y: (originY - point.y) / zoom + view.minY)
    }

    /// Lets go of the Capture's pixels. The mapping is unmapped once nothing else holds them.
    func tearDown() {
        imageLayer.contents = nil
        annotationLayers.tearDown()
        capture = nil
        effectLayer.sublayers = nil
        annotationLayer.sublayers = nil
        cropOverlay.tearDown()
        world.sublayers = nil
        selectionWorld.sublayers = nil
        clipLayer.sublayers = nil
        contentLayer.sublayers = nil
        root.sublayers = nil
        layer = nil
    }

    override func resetCursorRects() {
        guard let cursor = session?.currentTool.cursor else { return }
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let session else { return }
        session.currentTool.pointerDown(at: imagePoint(fromViewPoint: convert(event.locationInWindow, from: nil)), in: session)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let session else { return }
        session.currentTool.pointerDragged(to: imagePoint(fromViewPoint: convert(event.locationInWindow, from: nil)), in: session)
    }

    override func mouseUp(with event: NSEvent) {
        guard let session else { return }
        session.currentTool.pointerUp(at: imagePoint(fromViewPoint: convert(event.locationInWindow, from: nil)), in: session)
    }
}
