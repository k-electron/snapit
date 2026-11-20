import AppKit
import QuartzCore

/// What one display's scene shows right now. Positions are display-local points, top-left origin.
struct AreaSceneState: Equatable {
    /// The pointer is on this display.
    var hasPointer: Bool
    var cursor: CGPoint
    /// The frame of the window under the pointer, highlighted.
    var hoveredWindow: CGRect?
    /// The Area being dragged out.
    var selection: CGRect?
}

/// Every layer of the overlay on one display. They are created once; a pointer move changes some
/// of their frames and paths inside one transaction with actions disabled, so nothing animates
/// and nothing is ever redrawn (no `draw(_:)` anywhere: the frozen frame is the image layer's
/// contents, shared with the loupe).
///
/// Model space is points with the origin at the top left, like the pointer events; layers have
/// their origin at the bottom left, so every frame goes through `flipped`.
@MainActor
final class AreaOverlayScene {
    let root = CALayer()
    private let display: FrozenDisplay
    private let size: CGSize

    private let imageLayer = CALayer()
    private let dim = CAShapeLayer()
    private let hoverOuter = CAShapeLayer()
    private let hoverInner = CAShapeLayer()
    private let selectionRing = CAShapeLayer()
    private let verticalShadow = CALayer()
    private let horizontalShadow = CALayer()
    private let verticalLine = CALayer()
    private let horizontalLine = CALayer()
    private let sizeLabel: OverlayLabel
    private let loupe: OverlayLoupe

    private var dimmedCutout: CGRect?
    private var hasDimPath = false
    private var ringedHover: CGRect?
    private var ringedSelection: CGRect?
    private var shown: AreaSceneState?
    private var frameImage: CGImage?

    /// How many times `update` ran: one per pointer event that changed something.
    private(set) var updateCount = 0

    init(display: FrozenDisplay) {
        self.display = display
        size = display.frame.size
        let contentsScale = CGFloat(display.scale)
        sizeLabel = OverlayLabel(scale: contentsScale)
        loupe = OverlayLoupe(scale: contentsScale)

        root.backgroundColor = CGColor(gray: 0, alpha: 1)
        let bounds = CGRect(origin: .zero, size: size)

        imageLayer.frame = bounds
        // The layer shows the screenshot as it is; the loupe samples the same image.
        frameImage = display.image
        imageLayer.contents = frameImage
        imageLayer.contentsGravity = .resize
        imageLayer.contentsScale = contentsScale
        imageLayer.magnificationFilter = .nearest
        root.addSublayer(imageLayer)

        dim.frame = bounds
        dim.fillRule = .evenOdd
        dim.fillColor = CGColor(gray: 0, alpha: 0.4)
        root.addSublayer(dim)

        for ring in [hoverOuter, hoverInner, selectionRing] {
            ring.frame = bounds
            ring.isHidden = true
            ring.fillColor = nil
            ring.lineJoin = .miter
            root.addSublayer(ring)
        }
        hoverOuter.strokeColor = CGColor(gray: 1, alpha: 1)
        hoverOuter.lineWidth = 3
        hoverInner.strokeColor = NSColor.systemBlue.cgColor
        hoverInner.lineWidth = 1
        selectionRing.strokeColor = CGColor(gray: 1, alpha: 1)
        selectionRing.lineWidth = 1

        for (line, color) in [
            (verticalShadow, CGColor(gray: 0, alpha: 0.45)), (horizontalShadow, CGColor(gray: 0, alpha: 0.45)),
            (verticalLine, CGColor(gray: 1, alpha: 0.85)), (horizontalLine, CGColor(gray: 1, alpha: 0.85)),
        ] {
            line.backgroundColor = color
            line.isHidden = true
            root.addSublayer(line)
        }
        root.addSublayer(sizeLabel.layer)
        root.addSublayer(loupe.layer)
    }

    /// Model rectangle (top-left origin) to layer rectangle (bottom-left origin).
    private func flipped(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
    }

    func update(_ state: AreaSceneState) {
        // A display the pointer is not on, and a move inside the same point, change nothing.
        guard state != shown else { return }
        shown = state
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        updateCount += 1

        let selection = state.selection
        let hover = selection == nil ? state.hoveredWindow : nil
        setDim(cutout: selection ?? hover)
        // A path is rebuilt only when its rectangle changes.
        hoverOuter.isHidden = hover == nil
        hoverInner.isHidden = hover == nil
        if let hover, hover != ringedHover {
            hoverOuter.path = CGPath(rect: flipped(hover.insetBy(dx: 1.5, dy: 1.5)), transform: nil)
            hoverInner.path = CGPath(rect: flipped(hover.insetBy(dx: 3.5, dy: 3.5)), transform: nil)
        }
        ringedHover = hover
        selectionRing.isHidden = selection == nil
        if let selection, selection != ringedSelection {
            selectionRing.path = CGPath(rect: flipped(selection.insetBy(dx: 0.5, dy: 0.5)), transform: nil)
        }
        ringedSelection = selection

        if let selection {
            let pixels = AreaGeometry.pixelRect(
                of: selection, scale: display.scale, width: display.image.width, height: display.image.height)
            sizeLabel.set(
                "\(pixels?.width ?? 0) × \(pixels?.height ?? 0)", fontSize: 12, weight: .semibold, color: .white,
                padX: 8, padY: 4, background: NSColor(white: 0, alpha: 0.8))
            var origin = CGPoint(x: selection.maxX + 8, y: selection.maxY + 8)
            if origin.x + sizeLabel.size.width > size.width - 4 {
                origin = CGPoint(x: selection.maxX - sizeLabel.size.width - 8, y: selection.maxY + 8)
            }
            if origin.y + sizeLabel.size.height > size.height - 4 {
                origin.y = selection.maxY - sizeLabel.size.height - 8
            }
            sizeLabel.place(topLeft: origin, parentHeight: size.height)
        } else {
            sizeLabel.hide()
        }

        guard state.hasPointer else {
            for line in [verticalShadow, horizontalShadow, verticalLine, horizontalLine] { line.isHidden = true }
            loupe.hide()
            return
        }
        placeCrosshair(at: state.cursor)
        if let frameImage {
            loupe.update(
                frame: frameImage, scale: display.scale, cursor: state.cursor, at: loupeOrigin(for: state.cursor),
                sceneHeight: size.height)
        }
    }

    /// Lets go of the frozen frame: no layer shows or samples it any more.
    func releaseFrame() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = nil
        loupe.releaseFrame()
        frameImage = nil
        CATransaction.commit()
    }

    /// The dim covers the display except `cutout`. The even-odd path changes only when the
    /// cutout does.
    private func setDim(cutout: CGRect?) {
        guard !hasDimPath || cutout != dimmedCutout else { return }
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: size))
        if let cutout { path.addRect(flipped(cutout)) }
        dim.path = path
        dimmedCutout = cutout
        hasDimPath = true
    }

    /// One pixel wide lines across the whole display, through the pixel under the pointer.
    private func placeCrosshair(at point: CGPoint) {
        let x = point.x.rounded(.down), y = point.y.rounded(.down)
        verticalShadow.frame = flipped(CGRect(x: x + 1, y: 0, width: 1, height: size.height))
        horizontalShadow.frame = flipped(CGRect(x: 0, y: y + 1, width: size.width, height: 1))
        verticalLine.frame = flipped(CGRect(x: x, y: 0, width: 1, height: size.height))
        horizontalLine.frame = flipped(CGRect(x: 0, y: y, width: size.width, height: 1))
        for line in [verticalShadow, horizontalShadow, verticalLine, horizontalLine] { line.isHidden = false }
    }

    /// Beside the pointer, flipping to its other side near the display's edges.
    private func loupeOrigin(for cursor: CGPoint) -> CGPoint {
        let loupeSize = OverlayLoupe.size
        var x = cursor.x + 24, y = cursor.y + 24
        if x + loupeSize.width > size.width - 4 { x = cursor.x - 24 - loupeSize.width }
        if y + loupeSize.height > size.height - 4 { y = cursor.y - 24 - loupeSize.height }
        return CGPoint(x: max(4, x), y: max(4, y))
    }
}
