import AppKit

/// A borderless panel that covers one display. It can take key (for Esc) but never main, and
/// never activates the app on its own.
final class AreaOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// The panel sits exactly on its display, even a display larger than the real screen the
    /// scripted run puts it on.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    init(frame: CGRect) {
        super.init(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isReleasedWhenClosed = false
        hasShadow = false
        isOpaque = true
        backgroundColor = .black
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setFrame(frame, display: false)
        // A scripted run sends its events straight to the panel; the user's own mouse passes
        // through it, and it never takes the keyboard.
        ignoresMouseEvents = TestMode.isActive
    }
}

/// The overlay's view for one display. Layer-hosting: it has no `draw(_:)`, every visual is a
/// persistent layer of its `AreaOverlayScene`. It only turns events into display-local points
/// (origin at the top left) for the controller.
final class AreaOverlayView: NSView {
    private weak var controller: AreaOverlayController?
    let index: Int
    let scene: AreaOverlayScene

    init(frame: NSRect, index: Int, controller: AreaOverlayController, scene: AreaOverlayScene) {
        self.index = index
        self.controller = controller
        self.scene = scene
        super.init(frame: frame)
        layer = scene.root  // layer-hosting: assign the layer first, then ask for layers
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Keys are handled by the controller's monitor; the view only keeps them from beeping.
    override func keyDown(with event: NSEvent) {}

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil))
    }

    private func point(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: local.x, y: bounds.height - local.y)
    }

    override func cursorUpdate(with event: NSEvent) { controller?.updateCursor() }
    override func mouseEntered(with event: NSEvent) {
        guard controller?.acceptsPointer(on: index) ?? false else { return }
        if !TestMode.isActive { window?.makeKey() }
        controller?.mouseMoved(index, point(event))
    }
    override func mouseMoved(with event: NSEvent) {
        guard controller?.acceptsPointer(on: index) ?? false else { return }
        controller?.mouseMoved(index, point(event))
    }
    override func mouseDown(with event: NSEvent) { controller?.mouseDown(index, point(event), clickCount: event.clickCount) }
    override func mouseDragged(with event: NSEvent) { controller?.mouseDragged(index, point(event)) }
    override func mouseUp(with event: NSEvent) { controller?.mouseUp(index, point(event)) }
}
