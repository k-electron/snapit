import AppKit
import QuartzCore

/// The Editor's canvas: a layer-hosting view. Core Animation layers hold everything, the view
/// has no `draw(_:)`, and nothing ever asks it to redraw. The Capture is one layer whose
/// contents read the Capture file's mapping in place.
///
/// Layers, back to front: `root` > `contentLayer` (the Capture's size in points, scaled to
/// fit and centred) > `imageLayer` (the Capture), then `annotationLayer` on top. A tool adds
/// its layers to `annotationLayer`, whose geometry is flipped: positions are image points,
/// origin at the top left, the same coordinates the tool receives from the pointer.
@MainActor
final class CanvasView: NSView {
    /// The Capture's size in points, scaled to fit the view.
    let contentLayer = CALayer()
    /// Where tools put their layers, in image points, origin at the top left.
    let annotationLayer = CALayer()
    private let root = CALayer()
    private let imageLayer = CALayer()
    private let pointSize: CGSize
    weak var session: EditorSession?

    /// Space kept free around the Capture.
    var padding: CGFloat = 6

    init(image: CGImage, pointSize: CGSize, backingScale: CGFloat) {
        self.pointSize = pointSize
        super.init(frame: .zero)
        // Layer-hosting: the layer is set before `wantsLayer`, so AppKit never draws into it.
        layer = root
        wantsLayer = true

        contentLayer.bounds = CGRect(origin: .zero, size: pointSize)
        annotationLayer.frame = contentLayer.bounds
        annotationLayer.isGeometryFlipped = true
        imageLayer.frame = contentLayer.bounds
        imageLayer.contents = image
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        imageLayer.magnificationFilter = .nearest
        imageLayer.contentsScale = backingScale
        contentLayer.addSublayer(imageLayer)
        contentLayer.addSublayer(annotationLayer)
        root.addSublayer(contentLayer)
    }

    required init?(coder: NSCoder) { fatalError("CanvasView is made in code") }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
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
    }

    /// A point in the view, as a point of the Capture (origin at its top left).
    func imagePoint(fromViewPoint point: CGPoint) -> CGPoint {
        let zoom = zoom
        let originX = bounds.midX - pointSize.width * zoom / 2
        let originY = bounds.midY + pointSize.height * zoom / 2
        return CGPoint(x: (point.x - originX) / zoom, y: (originY - point.y) / zoom)
    }

    /// Lets go of the Capture's pixels. The mapping is unmapped once nothing else holds them.
    func tearDown() {
        imageLayer.contents = nil
        annotationLayer.sublayers = nil
        contentLayer.sublayers = nil
        root.sublayers = nil
        layer = nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        session?.currentTool.pointerDown(at: imagePoint(fromViewPoint: convert(event.locationInWindow, from: nil)), in: session!)
    }

    override func mouseDragged(with event: NSEvent) {
        session?.currentTool.pointerDragged(to: imagePoint(fromViewPoint: convert(event.locationInWindow, from: nil)), in: session!)
    }

    override func mouseUp(with event: NSEvent) {
        session?.currentTool.pointerUp(at: imagePoint(fromViewPoint: convert(event.locationInWindow, from: nil)), in: session!)
    }
}
