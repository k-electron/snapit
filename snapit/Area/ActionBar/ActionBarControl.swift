import AppKit
import QuartzCore

/// How long the pointer rests on a tile of the Action bar, or on the Timed Capture's cancel button,
/// before its tooltip shows.
enum TooltipTiming {
    static let restDelay: TimeInterval = 0.5
}

/// One tile of the Action bar, as persistent layers. The bar sets its frame; the overlay's
/// controller hit-tests the tile's rectangle, so a tile is a full-size hit area, and calls the
/// pointer hooks with points in the tile's own space (points, origin at its top left).
///
/// A control with its own behaviour (a slider that follows a drag) subclasses this: it sets
/// `preferredSize`, adds its layers to `layer` in `didLayout()` (the layer's bounds are the
/// tile's) and overrides the pointer hooks. It changes layers only inside
/// `CATransaction.setDisableActions(true)`, as the bar's callers already do.
@MainActor
class ActionBarControl {
    let id: String
    let tooltip: String
    let layer = CALayer()
    /// The size the tile asks for; the bar lays tiles out left to right at this size.
    var preferredSize: CGSize
    /// The tile in the bar's space (top-left origin), set by the bar.
    private(set) var frame = CGRect.zero

    /// The pointer is over the tile.
    var isHovered = false {
        didSet { if isHovered != oldValue { stateChanged() } }
    }
    /// The mouse button went down on the tile and has not come up.
    var isPressed = false {
        didSet { if isPressed != oldValue { stateChanged() } }
    }

    init(id: String, tooltip: String, preferredSize: CGSize) {
        self.id = id
        self.tooltip = tooltip
        self.preferredSize = preferredSize
        layer.bounds = CGRect(origin: .zero, size: preferredSize)
    }

    /// Puts the tile at `frame` in a bar `barHeight` tall.
    func layout(in frame: CGRect, barHeight: CGFloat) {
        self.frame = frame
        layer.frame = CGRect(x: frame.minX, y: barHeight - frame.maxY, width: frame.width, height: frame.height)
        didLayout()
    }

    /// The tile's size is set (`layer.bounds`).
    func didLayout() {}
    /// Hover or press changed.
    func stateChanged() {}
    func pointerDown(at point: CGPoint) {}
    func pointerDragged(at point: CGPoint) {}
    /// The button came up; `inside` when the pointer is over the tile.
    func pointerUp(at point: CGPoint, inside: Bool) {}
}

/// The standard tile: a rounded rectangle with an optional glyph and a title. Pressing and
/// releasing on it runs the item.
final class ActionBarButtonControl: ActionBarControl {
    enum Look { case plain, prominent }

    static let height: CGFloat = 34

    private let item: any ActionBarItem
    private let host: any ActionBarHost
    private let look: Look
    private let glyphLayer = CAShapeLayer()
    private let titleLayer = CATextLayer()
    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)

    /// `widestTitle` sizes the tile for a title that changes (`setTitle`): the longest it will
    /// have. By default the item's own title.
    init(item: any ActionBarItem, context: ActionBarContext, widestTitle: String? = nil) {
        self.item = item
        host = context.host
        look = item.look
        let font = Self.font
        let textWidth = ceil(
            NSAttributedString(string: widestTitle ?? item.title, attributes: [.font: font]).size().width)
        let glyphWidth: CGFloat = item.glyph == nil ? 0 : Self.glyphSize + 6
        super.init(
            id: item.id, tooltip: item.tooltip,
            preferredSize: CGSize(width: max(84, 28 + glyphWidth + textWidth), height: Self.height))

        layer.cornerRadius = Self.height / 2
        titleLayer.string = NSAttributedString(
            string: item.title,
            attributes: [.font: font, .foregroundColor: NSColor.white])
        titleLayer.contentsScale = context.scale
        titleLayer.isWrapped = false
        titleLayer.alignmentMode = .left
        titleLayer.bounds = CGRect(x: 0, y: 0, width: textWidth + 2, height: ceil(font.boundingRectForFont.height))
        layer.addSublayer(titleLayer)

        if let glyph = item.glyph {
            glyphLayer.path = glyph
            glyphLayer.bounds = CGRect(x: 0, y: 0, width: Self.glyphSize, height: Self.glyphSize)
            glyphLayer.strokeColor = CGColor(gray: 1, alpha: 1)
            glyphLayer.fillColor = nil
            glyphLayer.lineWidth = 1.6
            glyphLayer.lineCap = .round
            glyphLayer.lineJoin = .round
            layer.addSublayer(glyphLayer)
        }
        setTitle(item.title)
        stateChanged()
    }

    private static let glyphSize: CGFloat = 14

    /// Shows `title` on the button, centred with the glyph in the tile (a button whose words
    /// change, like "Capture in 7 s", is sized for its longest by `widestTitle`).
    func setTitle(_ title: String) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        titleLayer.string = NSAttributedString(
            string: title, attributes: [.font: Self.font, .foregroundColor: NSColor.white])
        let textWidth = ceil(NSAttributedString(string: title, attributes: [.font: Self.font]).size().width)
        titleLayer.bounds.size.width = textWidth + 2
        let glyphWidth: CGFloat = item.glyph == nil ? 0 : Self.glyphSize + 6
        let left = (preferredSize.width - (glyphWidth + textWidth)) / 2
        let middle = preferredSize.height / 2
        if item.glyph != nil {
            glyphLayer.position = CGPoint(x: left + Self.glyphSize / 2, y: middle)
        }
        titleLayer.position = CGPoint(x: left + glyphWidth + titleLayer.bounds.width / 2, y: middle)
        CATransaction.commit()
    }

    override func stateChanged() {
        let color: CGColor
        switch look {
        case .plain: color = CGColor(gray: 1, alpha: isPressed ? 0.26 : isHovered ? 0.16 : 0)
        case .prominent:
            let accent = NSColor.controlAccentColor
            color = accent.withAlphaComponent(isPressed ? 0.72 : isHovered ? 0.92 : 1).cgColor
        }
        layer.backgroundColor = color
    }

    override func pointerUp(at point: CGPoint, inside: Bool) {
        if inside { item.perform(on: host) }
    }
}
