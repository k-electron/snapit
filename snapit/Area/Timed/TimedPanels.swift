import AppKit
import QuartzCore

/// A borderless panel of the countdown: above everything, on every Space, never key, never
/// activating snapit. Only the badge takes clicks; the border and the tooltip are click-through.
final class TimedPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// A panel sits exactly where it is put, even partly off the display (a border around an Area
    /// that touches the display's edge).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    init(frame: CGRect, takesClicks: Bool) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // A scripted run sends its events straight to the panel; the user's own mouse passes
        // through it.
        ignoresMouseEvents = !takesClicks || TestMode.isActive
        setFrame(frame, display: false)
    }

    /// The panel's content: one layer-hosting view, with `layer` as its root, filling the panel.
    func host(_ layer: CALayer) {
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.layer = layer  // layer-hosting: assign the layer first, then ask for layers
        view.wantsLayer = true
        contentView = view
    }
}

/// The countdown badge: the seconds left, and a ✕ on its right that cancels. Persistent layers,
/// changed inside a transaction with actions disabled. The ✕ fires on mouse-up, and only when the
/// press began on it too.
final class TimedBadgeView: NSView {
    static let crossWidth: CGFloat = 32

    var onCancel: (() -> Void)?
    /// The pointer moved onto or off the ✕.
    var onCrossHover: ((Bool) -> Void)?

    private let root = CALayer()
    private let seconds = CATextLayer()
    private let divider = CALayer()
    private let crossBackground = CALayer()
    private let cross = CAShapeLayer()
    private var pressedOnCross = false
    private var isOverCross = false

    init(scale: CGFloat, seconds value: Int) {
        let size = TimedBadgePlacement.size
        super.init(frame: CGRect(origin: .zero, size: size))
        root.bounds = CGRect(origin: .zero, size: size)
        root.backgroundColor = CGColor(gray: 0.08, alpha: 0.94)
        root.cornerRadius = size.height / 2
        root.borderColor = CGColor(gray: 1, alpha: 0.35)
        root.borderWidth = 1

        let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
        let line = ceil(font.boundingRectForFont.height)
        let labelWidth = size.width - Self.crossWidth
        seconds.contentsScale = scale
        seconds.isWrapped = false
        seconds.alignmentMode = .center
        seconds.frame = CGRect(x: 0, y: (size.height - line) / 2, width: labelWidth, height: line)
        root.addSublayer(seconds)

        divider.backgroundColor = CGColor(gray: 1, alpha: 0.25)
        divider.frame = CGRect(x: labelWidth, y: 6, width: 1, height: size.height - 12)
        root.addSublayer(divider)

        let center = CGPoint(x: size.width - Self.crossWidth / 2 + 0.5, y: size.height / 2)
        crossBackground.bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
        crossBackground.cornerRadius = 11
        crossBackground.position = center
        root.addSublayer(crossBackground)
        // The ✕ as a path: no glyph, so no fallback font.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -4, y: -4))
        path.addLine(to: CGPoint(x: 4, y: 4))
        path.move(to: CGPoint(x: -4, y: 4))
        path.addLine(to: CGPoint(x: 4, y: -4))
        cross.path = path
        cross.position = center
        cross.strokeColor = CGColor(gray: 1, alpha: 1)
        cross.fillColor = nil
        cross.lineWidth = 2
        cross.lineCap = .round
        root.addSublayer(cross)

        layer = root  // layer-hosting: assign the layer first, then ask for layers
        wantsLayer = true
        show(seconds: value)
        showCrossState()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(seconds value: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
        seconds.string = NSAttributedString(
            string: "\(value) s", attributes: [.font: font, .foregroundColor: NSColor.white])
        CATransaction.commit()
    }

    private func showCrossState() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        crossBackground.backgroundColor = CGColor(gray: 1, alpha: pressedOnCross ? 0.32 : isOverCross ? 0.2 : 0)
        CATransaction.commit()
    }

    private func isOnCross(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        return bounds.contains(point) && point.x >= bounds.width - Self.crossWidth
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        (isOnCross(event) ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    private func hover(_ event: NSEvent) {
        let over = isOnCross(event)
        guard over != isOverCross else { return }
        isOverCross = over
        showCrossState()
        onCrossHover?(over)
    }

    override func mouseEntered(with event: NSEvent) { hover(event) }
    override func mouseMoved(with event: NSEvent) { hover(event) }
    override func mouseExited(with event: NSEvent) {
        guard isOverCross else { return }
        isOverCross = false
        showCrossState()
        onCrossHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        pressedOnCross = isOnCross(event)
        showCrossState()
        if pressedOnCross { onCrossHover?(false) }
    }

    /// Fires on mouse-up over the ✕ after a press that began on it. Deferred: cancelling closes
    /// this very panel, which must not happen inside its own event handler.
    override func mouseUp(with event: NSEvent) {
        let fires = pressedOnCross && isOnCross(event)
        pressedOnCross = false
        showCrossState()
        if fires { DispatchQueue.main.async { [weak self] in self?.onCancel?() } }
    }
}

/// A hover tooltip for the ✕, in its own click-through panel (the system's tooltip window sits
/// below the countdown's level). Made when the pointer has rested on the ✕, closed when it moves.
@MainActor
final class TimedTooltip {
    private(set) var panel: TimedPanel?
    private(set) var text: String?

    /// Shows `text` below `badge` (display-local points, top-left origin), or above it when there
    /// is no room below, inside the display `frame` (AppKit global space).
    func show(_ text: String, near badge: CGRect, in frame: CGRect, scale: CGFloat) {
        close()
        let label = OverlayLabel(scale: scale)
        label.set(
            text, fontSize: 12, weight: .medium, color: .white, padX: 10, padY: 4,
            background: NSColor(white: 0, alpha: 0.85))
        let size = label.size
        var top = badge.maxY + 6
        if top + size.height > frame.height - 4 { top = badge.minY - 6 - size.height }
        let left = max(4, min(frame.width - 4 - size.width, badge.midX - size.width / 2))
        let global = CGRect(x: frame.minX + left, y: frame.maxY - top - size.height, width: size.width, height: size.height)

        let root = CALayer()
        root.bounds = CGRect(origin: .zero, size: size)
        root.addSublayer(label.layer)
        label.place(topLeft: .zero, parentHeight: size.height)
        let panel = TimedPanel(frame: global, takesClicks: false)
        panel.host(root)
        panel.orderFrontRegardless()
        self.panel = panel
        self.text = text
    }

    func close() {
        guard let panel else { return }
        panel.contentView = nil
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
        text = nil
    }
}
