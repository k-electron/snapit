import AppKit
import QuartzCore

/// A tooltip for a tile of the Action bar, drawn in the scene (the system's tooltip window sits
/// below the overlay's level).
struct AreaTooltip: Equatable {
    var text: String
    /// The tile it is about, display-local points.
    var anchor: CGRect
}

/// What one display's scene shows right now. Positions are display-local points, top-left origin.
struct AreaSceneState: Equatable {
    /// The crosshair and loupe show here: the pointer is on this display and no Area is being
    /// adjusted.
    var hasPointer: Bool
    var cursor: CGPoint
    /// The frame of the window under the pointer, highlighted.
    var hoveredWindow: CGRect?
    /// The Area being dragged out or adjusted.
    var selection: CGRect?
    /// The Area is being adjusted: its eight handles show.
    var showsHandles = false
    /// The Action bar's frame on this display, when it shows. The size label keeps clear of it.
    var actionBar: CGRect?
    var tooltip: AreaTooltip?
    /// The Color picker is up on this display: its loupe shows, and the dim, selection, crosshair
    /// and the overlay's own loupe do not.
    var picker: PickerSceneState?
}

/// What the Color picker's loupe shows on one display.
struct PickerSceneState: Equatable {
    /// The sampled device pixel and its color.
    var pixel: PixelPoint
    var color: PixelColor
    /// The pointer, display-local points: the loupe sits beside it.
    var cursor: CGPoint
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
    private let handles = (0..<8).map { _ in CALayer() }
    private let verticalShadow = CALayer()
    private let horizontalShadow = CALayer()
    private let verticalLine = CALayer()
    private let horizontalLine = CALayer()
    private let sizeLabel: OverlayLabel
    private let tooltipLabel: OverlayLabel
    private let loupe: OverlayLoupe
    /// The Color picker's loupe, made the first time a picker is shown.
    private var pickLoupe: PickLoupe?

    private var dimmedCutout: CGRect?
    private var hasDimPath = false
    private var ringedHover: CGRect?
    private var ringedSelection: CGRect?
    private var handledSelection: CGRect?
    private var shown: AreaSceneState?
    private var frameImage: CGImage?

    /// A handle is a square this many points wide, centred on its corner or edge.
    static let handleSize: CGFloat = 9

    /// The loupe is showing.
    var isLoupeShown: Bool { !loupe.layer.isHidden }

    /// The Color picker's loupe is showing.
    var isPickLoupeShown: Bool { pickLoupe?.isShown == true }

    /// The Color picker's loupe frame in display points, top-left origin, when it shows.
    var pickLoupeFrame: CGRect? {
        guard let pickLoupe, pickLoupe.isShown else { return nil }
        let frame = pickLoupe.layer.frame
        return CGRect(x: frame.minX, y: size.height - frame.maxY, width: frame.width, height: frame.height)
    }

    /// How many handles are showing.
    var visibleHandles: Int { handles.filter { !$0.isHidden }.count }

    /// How many times `update` ran: one per pointer event that changed something.
    private(set) var updateCount = 0

    init(display: FrozenDisplay) {
        self.display = display
        size = display.frame.size
        let contentsScale = CGFloat(display.scale)
        sizeLabel = OverlayLabel(scale: contentsScale)
        tooltipLabel = OverlayLabel(scale: contentsScale)
        loupe = OverlayLoupe(scale: contentsScale)

        root.backgroundColor = CGColor(gray: 0, alpha: 1)
        let bounds = CGRect(origin: .zero, size: size)

        imageLayer.frame = bounds
        // The layer shows the captured frame as it is; the loupe samples the same image.
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

        for handle in handles {
            handle.bounds = CGRect(x: 0, y: 0, width: Self.handleSize, height: Self.handleSize)
            handle.backgroundColor = CGColor(gray: 1, alpha: 1)
            handle.borderColor = CGColor(gray: 0, alpha: 0.55)
            handle.borderWidth = 1
            handle.cornerRadius = 2
            handle.isHidden = true
            root.addSublayer(handle)
        }

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
        root.addSublayer(tooltipLabel.layer)
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

        // The selection is drawn where its device pixels are, which is what the Capture holds.
        let pixels = state.selection.flatMap {
            AreaGeometry.pixelRect(
                of: $0, scale: display.scale, width: display.image.width, height: display.image.height)
        }
        let selection = pixels.map { AreaGeometry.points(of: $0, scale: display.scale) }
        let hover = selection == nil ? state.hoveredWindow : nil
        setDim(cutout: selection ?? hover)
        // Aiming at a color shows the frame as it is: no dim over what is being read.
        dim.isHidden = state.picker != nil
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

        let handled = state.showsHandles ? selection : nil
        if handled != handledSelection {
            handledSelection = handled
            for handle in handles { handle.isHidden = handled == nil }
            if let handled { placeHandles(around: handled) }
        }

        if let selection, let pixels {
            sizeLabel.set(
                "\(pixels.width) × \(pixels.height)", fontSize: 12, weight: .semibold, color: .white,
                padX: 8, padY: 4, background: NSColor(white: 0, alpha: 0.8))
            sizeLabel.place(
                topLeft: labelOrigin(for: selection, adjusting: state.showsHandles, avoiding: state.actionBar),
                parentHeight: size.height)
        } else {
            sizeLabel.hide()
        }

        placeTooltip(state.tooltip, bar: state.actionBar)

        placePicker(state.picker)
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

    /// The Color picker's loupe beside the pointer, or gone.
    private func placePicker(_ picker: PickerSceneState?) {
        guard let picker, let frameImage else {
            pickLoupe?.hide()
            return
        }
        let loupe = pickLoupe ?? PickLoupe(scale: CGFloat(display.scale))
        if pickLoupe == nil {
            pickLoupe = loupe
            root.addSublayer(loupe.layer)
            // Above the tooltip's layer too: nothing else shows while a color is picked.
        }
        var origin = CGPoint(x: picker.cursor.x + 24, y: picker.cursor.y + 24)
        let loupeSize = PickLoupe.size
        if origin.x + loupeSize.width > size.width - 4 { origin.x = picker.cursor.x - 24 - loupeSize.width }
        if origin.y + loupeSize.height > size.height - 4 { origin.y = picker.cursor.y - 24 - loupeSize.height }
        loupe.update(
            frame: frameImage, pixel: picker.pixel, color: picker.color,
            at: CGPoint(x: max(4, origin.x), y: max(4, origin.y)), sceneHeight: size.height)
    }

    /// The tooltip goes below the Action bar, or above it when there is no room below.
    private func placeTooltip(_ tooltip: AreaTooltip?, bar: CGRect?) {
        guard let tooltip, let bar else {
            tooltipLabel.hide()
            return
        }
        tooltipLabel.set(
            tooltip.text, fontSize: 12, weight: .medium, color: .white, padX: 10, padY: 4,
            background: NSColor(white: 0, alpha: 0.85))
        let label = tooltipLabel.size
        var y = bar.maxY + 6
        if y + label.height > size.height - 4 { y = bar.minY - 6 - label.height }
        let x = max(4, min(size.width - 4 - label.width, tooltip.anchor.midX - label.width / 2))
        tooltipLabel.place(topLeft: CGPoint(x: x, y: y), parentHeight: size.height)
    }

    /// The eight handles, clockwise from the top left corner.
    private func placeHandles(around selection: CGRect) {
        let centres = [
            CGPoint(x: selection.minX, y: selection.minY), CGPoint(x: selection.midX, y: selection.minY),
            CGPoint(x: selection.maxX, y: selection.minY), CGPoint(x: selection.maxX, y: selection.midY),
            CGPoint(x: selection.maxX, y: selection.maxY), CGPoint(x: selection.midX, y: selection.maxY),
            CGPoint(x: selection.minX, y: selection.maxY), CGPoint(x: selection.minX, y: selection.midY),
        ]
        for (handle, centre) in zip(handles, centres) {
            handle.position = CGPoint(x: centre.x, y: size.height - centre.y)
        }
    }

    /// While an Area is dragged out its size sits below its bottom-right corner. While it is
    /// adjusted the label goes above its top-left corner, so the Action bar (below it) and the
    /// handles stay clear; with no room above, or when the bar is there, it moves inside.
    private func labelOrigin(for selection: CGRect, adjusting: Bool, avoiding bar: CGRect?) -> CGPoint {
        let label = sizeLabel.size
        guard adjusting else {
            var origin = CGPoint(x: selection.maxX + 8, y: selection.maxY + 8)
            if origin.x + label.width > size.width - 4 {
                origin = CGPoint(x: selection.maxX - label.width - 8, y: selection.maxY + 8)
            }
            if origin.y + label.height > size.height - 4 { origin.y = selection.maxY - label.height - 8 }
            return origin
        }
        var origin = CGPoint(x: max(4, selection.minX), y: selection.minY - label.height - 8)
        if origin.y < 4 { origin = CGPoint(x: selection.minX + 8, y: selection.minY + 8) }
        if let bar, bar.insetBy(dx: -4, dy: -4).intersects(CGRect(origin: origin, size: label)) {
            origin = CGPoint(x: selection.minX + 8, y: selection.minY + 8)
        }
        return origin
    }

    /// Lets go of the frozen frame: no layer shows or samples it any more.
    func releaseFrame() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = nil
        loupe.releaseFrame()
        pickLoupe?.releaseFrame()
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
