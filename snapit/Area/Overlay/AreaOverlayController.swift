import AppKit

/// What the user chose in the overlay: an Area of one display, in whole device pixels.
struct AreaSelection: Equatable {
    /// Index into the displays the overlay was shown for.
    let displayIndex: Int
    let pixels: PixelRect
}

/// The Area overlay: one panel per frozen display, the pointer state machine and the keyboard.
///
/// "After selecting an Area" is Capture on release: letting go of the mouse after a drag, or a
/// click on the highlighted window, finishes with that selection. Esc finishes with nil.
/// The controller keeps no pixels of its own; the frozen frames belong to the scenes' layers
/// and go with the panels at `teardown()`.
@MainActor
final class AreaOverlayController {
    enum State: String {
        case idle, hoverWindow, dragging
    }

    let displays: [FrozenDisplay]
    private let windows: [OnScreenWindow]
    private let pointer: CGPoint
    private(set) var panels: [AreaOverlayPanel] = []
    private(set) var views: [AreaOverlayView] = []
    private var monitor: Any?

    /// Called once, on a later turn of the run loop (never from inside an event handler of one of
    /// the overlay's own windows, which the caller is about to close).
    var onFinish: ((AreaSelection?) -> Void)?
    private(set) var isFinished = false

    private(set) var state = State.idle
    private(set) var activeIndex = 0
    private(set) var cursor = CGPoint.zero
    private(set) var selection: CGRect?
    private(set) var selectionIndex: Int?
    private(set) var hoveredWindow: CGRect?

    // The gesture in progress.
    private var isPressed = false
    private var hasMovedPastThreshold = false
    private var pressedIndex = 0
    private var anchor = CGPoint.zero

    /// A press that moves less than this many points is a click, not a drag.
    static let dragThreshold: CGFloat = 3

    init(displays: [FrozenDisplay], windows: [OnScreenWindow], pointer: CGPoint) {
        self.displays = displays
        self.windows = windows
        self.pointer = pointer
    }

    // MARK: Showing and tearing down

    /// Puts a panel on every display. `takesFocus` is false in a scripted run, which never
    /// activates snapit or takes the keyboard from what the user is doing.
    func show(takesFocus: Bool) {
        activeIndex = displays.firstIndex { $0.frame.contains(pointer) } ?? 0
        let active = displays[activeIndex]
        cursor = AreaGeometry.clamp(
            CGPoint(x: pointer.x - active.frame.minX, y: active.frame.maxY - pointer.y), to: active.bounds)

        for (index, display) in displays.enumerated() {
            let panel = AreaOverlayPanel(frame: display.frame)
            let scene = AreaOverlayScene(display: display)
            let view = AreaOverlayView(
                frame: CGRect(origin: .zero, size: display.frame.size), index: index, controller: self, scene: scene)
            panel.contentView = view
            panel.setFrame(display.frame, display: false)
            panels.append(panel)
            views.append(view)
        }
        refreshHover()
        refreshScenes()

        for (index, panel) in panels.enumerated() where index != activeIndex { panel.orderFrontRegardless() }
        if takesFocus {
            panels[activeIndex].makeKeyAndOrderFront(nil)
            NSApp.activate()
            panels[activeIndex].makeFirstResponder(views[activeIndex])
        } else {
            panels[activeIndex].orderFrontRegardless()
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, !self.isFinished else { return event }
            return self.handle(event) ? nil : event
        }
        updateCursor()
        CATransaction.flush()
    }

    /// Closes every panel and lets go of every frozen frame.
    func teardown() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for view in views { view.scene.releaseFrame() }
        for panel in panels {
            panel.contentView = nil
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        views.removeAll()
        // Core Animation holds on to what it last committed until the next commit: do it now, so
        // the frozen frames are freed with the overlay and not at some later event.
        CATransaction.flush()
        onFinish = nil
        if !TestMode.isActive { NSCursor.arrow.set() }
    }

    // MARK: Pointer

    /// A pointer that is dragging out an Area stays with the display it started on.
    func acceptsPointer(on index: Int) -> Bool {
        !isPressed || index == pressedIndex
    }

    func mouseMoved(_ index: Int, _ point: CGPoint) {
        guard !isFinished else { return }
        setCursor(index, point)
        refreshHover()
        updateCursor()
        refreshScenes()
    }

    func mouseDown(_ index: Int, _ point: CGPoint) {
        guard !isFinished else { return }
        setCursor(index, point)
        isPressed = true
        hasMovedPastThreshold = false
        pressedIndex = index
        anchor = cursor
    }

    func mouseDragged(_ index: Int, _ point: CGPoint) {
        guard !isFinished, isPressed, index == pressedIndex else { return }
        let clamped = AreaGeometry.clamp(point, to: displays[index].bounds)
        setCursor(index, clamped)
        if !hasMovedPastThreshold {
            guard hypot(clamped.x - anchor.x, clamped.y - anchor.y) >= Self.dragThreshold else { return }
            hasMovedPastThreshold = true
            selectionIndex = index
            hoveredWindow = nil
            state = .dragging
        }
        selection = AreaGeometry.rect(anchor, clamped)
        refreshScenes()
    }

    /// Letting go is the Capture: after a drag, the dragged Area; after a click on a highlighted
    /// window, that window's frame.
    func mouseUp(_ index: Int, _ point: CGPoint) {
        guard !isFinished, isPressed else { return }
        isPressed = false
        setCursor(index, hasMovedPastThreshold ? AreaGeometry.clamp(point, to: displays[index].bounds) : point)
        if hasMovedPastThreshold, let selection, let selectionIndex {
            confirm(selection, on: selectionIndex)
        } else if state == .hoverWindow, let hoveredWindow {
            confirm(hoveredWindow, on: activeIndex)
        }
        guard !isFinished else { return }
        updateCursor()
        refreshScenes()
    }

    private func setCursor(_ index: Int, _ point: CGPoint) {
        activeIndex = index
        cursor = AreaGeometry.clamp(point, to: displays[index].bounds)
    }

    /// The window under the pointer, from the list read when the Shortcut fired.
    private func refreshHover() {
        guard state == .idle || state == .hoverWindow else { return }
        let display = displays[activeIndex]
        hoveredWindow = nil
        for window in windows {
            let local = window.frame.offsetBy(dx: -display.cgOrigin.x, dy: -display.cgOrigin.y)
            if local.contains(cursor) {
                hoveredWindow = local.intersection(display.bounds)
                break
            }
        }
        state = hoveredWindow == nil ? .idle : .hoverWindow
    }

    func updateCursor() {
        if !TestMode.isActive { NSCursor.crosshair.set() }
    }

    // MARK: Keyboard

    private func handle(_ event: NSEvent) -> Bool {
        if event.type == .keyDown, event.modifierFlags.contains(.command) { return false }
        if event.type == .keyDown, event.keyCode == 53 { cancel() }
        // Every other key is swallowed while the overlay is up, so none of them beeps.
        return true
    }

    // MARK: Finishing

    func cancel() {
        finish(with: nil)
    }

    private func confirm(_ area: CGRect, on index: Int) {
        let display = displays[index]
        guard
            let pixels = AreaGeometry.pixelRect(
                of: area, scale: display.scale, width: display.image.width, height: display.image.height)
        else {
            // A selection with no pixels in it is refused; the overlay carries on.
            selection = nil
            selectionIndex = nil
            hoveredWindow = nil
            state = .idle
            refreshHover()
            return
        }
        finish(with: AreaSelection(displayIndex: index, pixels: pixels))
    }

    private func finish(with result: AreaSelection?) {
        guard !isFinished else { return }
        isFinished = true
        DispatchQueue.main.async { [weak self] in self?.onFinish?(result) }
    }

    // MARK: Scenes

    private func refreshScenes() {
        for (index, view) in views.enumerated() {
            view.scene.update(
                AreaSceneState(
                    hasPointer: index == activeIndex, cursor: cursor,
                    hoveredWindow: index == activeIndex ? hoveredWindow : nil,
                    selection: index == selectionIndex ? selection : nil))
        }
    }
}
