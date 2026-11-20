import AppKit

/// What the user chose in the overlay: an Area of one display, in whole device pixels.
struct AreaSelection: Equatable {
    /// Index into the displays the overlay was shown for.
    let displayIndex: Int
    let pixels: PixelRect
}

/// The Area overlay: one panel per frozen display, the pointer state machine and the keyboard.
///
/// What letting go of the mouse does is the setting "After selecting an Area". With Capture on
/// release, a drag or a click on the highlighted window finishes with that selection. With Show
/// Action bar (the default) the selection stays: the overlay is `adjusting`, with eight handles to
/// resize it, a drag inside it to move it, and the Action bar. Return, a double-click inside the
/// selection and the bar's Capture button finish with it; Esc and the bar's Cancel finish with
/// `.cancel`. The controller keeps no pixels of its own; the frozen frames belong to the scenes'
/// layers and go with the panels at `teardown()`.
@MainActor
final class AreaOverlayController: ActionBarHost {
    enum State: String {
        case idle, hoverWindow, dragging, adjusting
    }

    /// What the pressed mouse button is doing.
    private enum Gesture {
        case none, newArea, resize(AreaHandle), move
    }

    let displays: [FrozenDisplay]
    private let windows: [OnScreenWindow]
    private let pointer: CGPoint
    private(set) var panels: [AreaOverlayPanel] = []
    /// The scene view of each panel (layer-hosting), inside its container.
    private(set) var views: [AreaOverlayView] = []
    private(set) var containers: [AreaOverlayContainerView] = []
    private var monitor: Any?
    private var screenObserver: NSObjectProtocol?

    /// Called once, on a later turn of the run loop (never from inside an event handler of one of
    /// the overlay's own windows, which the caller is about to close).
    var onFinish: ((AreaOverlayOutcome) -> Void)?
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
    private var gesture = Gesture.none
    /// The selection when the button went down: resizing and moving work from it.
    private var pressedSelection = CGRect.zero

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
        activeIndex = displays.firstIndex { NSMouseInRect(pointer, $0.frame, false) } ?? 0
        let active = displays[activeIndex]
        cursor = AreaGeometry.clamp(
            CGPoint(x: pointer.x - active.frame.minX, y: active.frame.maxY - pointer.y), to: active.bounds)

        for (index, display) in displays.enumerated() {
            let panel = AreaOverlayPanel(frame: display.frame)
            let scene = AreaOverlayScene(display: display)
            let bounds = CGRect(origin: .zero, size: display.frame.size)
            let view = AreaOverlayView(frame: bounds, index: index, controller: self, scene: scene)
            let container = AreaOverlayContainerView(frame: bounds, sceneView: view)
            panel.contentView = container
            panel.setFrame(display.frame, display: false)
            panels.append(panel)
            views.append(view)
            containers.append(container)
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
        // The frozen frames belong to the displays as they were: a display plugged in, unplugged
        // or rearranged while the overlay is up ends it.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
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
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        for view in views { view.scene.releaseFrame() }
        for container in containers { container.releaseActionBar() }
        for panel in panels {
            panel.contentView = nil
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        views.removeAll()
        containers.removeAll()
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

    func mouseDown(_ index: Int, _ point: CGPoint, clickCount: Int = 1) {
        guard !isFinished else { return }
        setCursor(index, point)
        // A click on the Action bar is the bar's.
        if containers[index].actionBarFrame?.contains(cursor) == true { return }
        isPressed = true
        hasMovedPastThreshold = false
        pressedIndex = index
        anchor = cursor
        gesture = .newArea
        guard state == .adjusting, selectionIndex == index, let selection else { return }
        pressedSelection = selection
        if let handle = AreaHandle.hit(selection, at: cursor) {
            gesture = .resize(handle)
        } else if selection.contains(cursor) {
            if clickCount >= 2 {
                isPressed = false
                gesture = .none
                captureSelection()
                return
            }
            gesture = .move
        }
        updateCursor()
    }

    func mouseDragged(_ index: Int, _ point: CGPoint) {
        guard !isFinished, isPressed, index == pressedIndex else { return }
        let bounds = displays[index].bounds
        let clamped = AreaGeometry.clamp(point, to: bounds)
        setCursor(index, clamped)
        // A press that moves less than the threshold moves nothing: a double-click's jitter leaves
        // the selection where it is.
        if !hasMovedPastThreshold {
            guard hypot(clamped.x - anchor.x, clamped.y - anchor.y) >= Self.dragThreshold else { return }
            hasMovedPastThreshold = true
            if case .newArea = gesture {
                selectionIndex = index
                hoveredWindow = nil
                state = .dragging
            }
        }
        let delta = CGSize(width: clamped.x - anchor.x, height: clamped.y - anchor.y)
        switch gesture {
        case .newArea: selection = AreaGeometry.rect(anchor, clamped)
        case .resize(let handle): selection = handle.resized(pressedSelection, by: delta, in: bounds)
        case .move: selection = AreaHandle.moved(pressedSelection, by: delta, in: bounds)
        case .none: break
        }
        updateCursor()
        refreshScenes()
    }

    /// Letting go ends a gesture. A drag that made a new Area, or a click on a highlighted window,
    /// follows "After selecting an Area".
    func mouseUp(_ index: Int, _ point: CGPoint) {
        guard !isFinished, isPressed else { return }
        isPressed = false
        let ended = gesture
        gesture = .none
        setCursor(index, hasMovedPastThreshold ? AreaGeometry.clamp(point, to: displays[index].bounds) : point)
        if case .newArea = ended {
            if hasMovedPastThreshold {
                if let selection, let selectionIndex { select(selection, on: selectionIndex) }
            } else if state == .adjusting {
                // A click away from the selection lets it go.
                clearSelection()
            } else if state == .hoverWindow, let hoveredWindow {
                select(hoveredWindow, on: activeIndex)
            }
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

    /// The cursor: crosshair to select with, a resize cursor over a handle, a hand inside the
    /// selection, an arrow over the Action bar.
    func updateCursor() {
        guard !TestMode.isActive else { return }
        guard state == .adjusting, selectionIndex == activeIndex, let selection else {
            NSCursor.crosshair.set()
            return
        }
        if containers[activeIndex].actionBarFrame?.contains(cursor) == true {
            NSCursor.arrow.set()
        } else if case .resize(let handle) = gesture {
            handle.cursor.set()
        } else if let handle = AreaHandle.hit(selection, at: cursor) {
            handle.cursor.set()
        } else if selection.contains(cursor) {
            if case .move = gesture { NSCursor.closedHand.set() } else { NSCursor.openHand.set() }
        } else {
            NSCursor.crosshair.set()
        }
    }

    // MARK: The selection

    /// The selection shows with its handles and the Action bar. A selection with no pixels in it
    /// is refused and the overlay carries on selecting.
    private func select(_ area: CGRect, on index: Int) {
        switch CapturingSettings.afterSelectingArea {
        case .captureOnRelease:
            confirm(area, on: index)
        case .showActionBar:
            guard pixels(of: area, on: index) != nil else {
                clearSelection()
                return
            }
            selection = area
            selectionIndex = index
            hoveredWindow = nil
            state = .adjusting
        }
    }

    private func clearSelection() {
        selection = nil
        selectionIndex = nil
        hoveredWindow = nil
        state = .idle
        refreshHover()
    }

    private func pixels(of area: CGRect, on index: Int) -> PixelRect? {
        let display = displays[index]
        return AreaGeometry.pixelRect(
            of: area, scale: display.scale, width: display.image.width, height: display.image.height)
    }

    /// The Area now selected, in whole device pixels.
    var selectedArea: AreaSelection? {
        guard state == .adjusting, let selection, let selectionIndex,
            let pixels = pixels(of: selection, on: selectionIndex)
        else { return nil }
        return AreaSelection(displayIndex: selectionIndex, pixels: pixels)
    }

    /// Captures the selection as it is (Return, a double-click inside it).
    private func captureSelection() {
        guard let selection, let selectionIndex else { return }
        confirm(selection, on: selectionIndex)
    }

    // MARK: Keyboard

    private func handle(_ event: NSEvent) -> Bool {
        if event.type == .keyDown, event.modifierFlags.contains(.command) { return false }
        guard event.type == .keyDown else { return true }
        switch event.keyCode {
        case 53:
            cancel()
        case 36, 76:
            if state == .adjusting { captureSelection() }
        default:
            // The Action bar's items name their own keys (the Color picker's P).
            if state == .adjusting, !event.isARepeat,
                let item = ActionBarRegistry.item(forKey: event.charactersIgnoringModifiers)
            {
                item.perform(on: self)
            }
        }
        // Every other key is swallowed while the overlay is up, so none of them beeps.
        return true
    }

    // MARK: Finishing

    func cancel() {
        finish(with: .cancel)
    }

    private func confirm(_ area: CGRect, on index: Int) {
        guard let pixels = pixels(of: area, on: index) else {
            // A selection with no pixels in it is refused; the overlay carries on.
            clearSelection()
            refreshScenes()
            return
        }
        finish(with: .capture(AreaSelection(displayIndex: index, pixels: pixels)))
    }

    /// Ends the overlay with `outcome`, once.
    func finish(with outcome: AreaOverlayOutcome) {
        guard !isFinished else { return }
        isFinished = true
        DispatchQueue.main.async { [weak self] in self?.onFinish?(outcome) }
    }

    // MARK: Scenes

    private func refreshScenes() {
        let adjusting = state == .adjusting
        for (index, container) in containers.enumerated() {
            let showsSelection = index == selectionIndex
            var bar: CGRect?
            if adjusting, showsSelection, let selection {
                bar = container.showActionBar(for: selection, host: self)
            } else {
                container.hideActionBar()
            }
            // An adjusted Area has no crosshair or loupe, so a pointer move changes nothing.
            container.sceneView.scene.update(
                AreaSceneState(
                    hasPointer: index == activeIndex && !adjusting, cursor: adjusting ? .zero : cursor,
                    hoveredWindow: index == activeIndex ? hoveredWindow : nil,
                    selection: showsSelection ? selection : nil, showsHandles: adjusting && showsSelection,
                    actionBar: bar))
        }
    }
}
