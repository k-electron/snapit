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
/// Layers, back to front: `root` > `contentLayer` (the Capture's size in points, scaled to
/// fit and centred) > `imageLayer` (the Capture), then `annotationLayer` (clipped to the
/// Capture) and `selectionLayer` on top. `annotationLayers` keeps one layer per Annotation in
/// `annotationLayer`; both layers' geometry is flipped: positions are image points, origin at
/// the top left, the same coordinates a tool receives from the pointer.
@MainActor
final class CanvasView: NSView {
    /// The Capture's size in points, scaled to fit the view.
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
    private let imageLayer = CALayer()
    private var pointSize = CGSize(width: 1, height: 1)
    private var capture: PixelBuffer?
    private var captureScale = 1.0
    weak var session: EditorSession?
    /// The text being typed, if any (`CanvasView+Text.swift`).
    var textEditing: TextEditingController?
    /// The view beside the canvas that holds the text view of a text being typed.
    weak var textHost: NSView?

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
        contentLayer.addSublayer(imageLayer)
        contentLayer.addSublayer(effectLayer)
        contentLayer.addSublayer(annotationLayer)
        contentLayer.addSublayer(selectionLayer)
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
        contentLayer.bounds = CGRect(origin: .zero, size: self.pointSize)
        effectLayer.frame = contentLayer.bounds
        annotationLayer.frame = contentLayer.bounds
        selectionLayer.frame = contentLayer.bounds
        imageLayer.frame = contentLayer.bounds
        imageLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        imageLayer.contents = image
        CATransaction.commit()
        needsLayout = true
    }

    override var isOpaque: Bool { false }
    /// Not while a text is typed: AppKit would move the keyboard to the canvas on the very press
    /// that should only commit the text, and the text view's loss of it would commit first, so the
    /// same press would start another text box. `mouseDown` takes the keyboard back itself.
    override var acceptsFirstResponder: Bool { textEditing == nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// How many view points one Capture point takes: 1 until the Capture is bigger than the
    /// canvas, then it shrinks to fit.
    var zoom: CGFloat {
        let available = CGSize(width: max(bounds.width - 2 * padding, 1), height: max(bounds.height - 2 * padding, 1))
        return min(1, available.width / pointSize.width, available.height / pointSize.height)
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
        CATransaction.commit()
        annotationLayers.contextChanged(renderContext)
        textEditing?.reposition()
    }

    /// What a kind's preview layer is given.
    var renderContext: AnnotationRenderContext {
        AnnotationRenderContext(
            capture: capture, scale: captureScale, zoom: zoom, backingScale: window?.backingScaleFactor ?? 2)
    }

    /// Shows the Annotations, with `selected` outlined.
    func showAnnotations(_ annotations: [Annotation], selected: Annotation?) {
        annotationLayers.show(annotations, selected: selected, context: renderContext)
    }

    /// A point in the view, as a point of the Capture (origin at its top left).
    func imagePoint(fromViewPoint point: CGPoint) -> CGPoint {
        let zoom = zoom
        let originX = bounds.midX - pointSize.width * zoom / 2
        let originY = bounds.midY + pointSize.height * zoom / 2
        return CGPoint(x: (point.x - originX) / zoom, y: (originY - point.y) / zoom)
    }

    /// A point of the Capture (origin at its top left), as a point in the view.
    func viewPoint(fromImagePoint point: CGPoint) -> CGPoint {
        let zoom = zoom
        let originX = bounds.midX - pointSize.width * zoom / 2
        let originY = bounds.midY + pointSize.height * zoom / 2
        return CGPoint(x: originX + point.x * zoom, y: originY - point.y * zoom)
    }

    /// Lets go of the Capture's pixels. The mapping is unmapped once nothing else holds them.
    func tearDown() {
        imageLayer.contents = nil
        annotationLayers.tearDown()
        capture = nil
        textEditing?.tearDown()
        textEditing = nil
        effectLayer.sublayers = nil
        annotationLayer.sublayers = nil
        contentLayer.sublayers = nil
        root.sublayers = nil
        layer = nil
    }

    override func resetCursorRects() {
        guard let cursor = session?.currentTool.cursor else { return }
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        guard let session else { return }
        let point = imagePoint(fromViewPoint: convert(event.locationInWindow, from: nil))
        // A click while a text is typed only commits it, and a double click on a Text edits it:
        // both before the canvas takes the keyboard (that would end the typing on its own).
        if session.consumesPointerDown(at: point, clickCount: event.clickCount) { return }
        window?.makeFirstResponder(self)
        session.currentTool.pointerDown(at: point, in: session)
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
