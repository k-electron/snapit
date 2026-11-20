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
/// `.cancel`. The Color picker is a state of this same overlay (`pickingColor`): the selection, the
/// Action bar and the crosshair give way to a loupe on the one pixel being sampled. From the Action
/// bar, Esc goes back to it; opened from the menu or its Shortcut, the overlay starts in the picker
/// and Esc ends it. The controller keeps no pixels of its own; the frozen frames belong to the scenes'
/// layers and go with the panels at `teardown()`.
@MainActor
final class AreaOverlayController: ActionBarHost {
    enum State: String {
        case idle, hoverWindow, dragging, adjusting
        /// The Color picker: a loupe on one device pixel; click or Enter copies its hex.
        case pickingColor
    }

    /// What the pressed mouse button is doing.
    private enum Gesture {
        case none, newArea, resize(AreaHandle), move
        /// A press on a tile of the Action bar.
        case bar
        /// A press while the Color picker is up: letting go picks.
        case pick
    }

    let displays: [FrozenDisplay]
    /// What the overlay is for. The window overlay (Window Capture) highlights the window under the
    /// pointer and a click captures it; it has no drag, no selection and no Action bar.
    let mode: AreaOverlayMode
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
    /// The Color picker's sampled pixel while `state` is `pickingColor`.
    private(set) var picker: ColorPickerSession?
    /// The window under the pointer itself (`hoveredWindow` is its frame cut to the display).
    private(set) var hoveredOnScreenWindow: OnScreenWindow?

    // The gesture in progress.
    private var isPressed = false
    private var hasMovedPastThreshold = false
    private var pressedIndex = 0
    private var anchor = CGPoint.zero
    private var gesture = Gesture.none
    /// The tile a press on the Action bar went down on.
    private var pressedTile: ActionBarControl?
    /// The tile under the pointer, and the tooltip for it once the pointer has rested there.
    private(set) var hoveredTile: ActionBarControl?
    private(set) var tooltip: String?
    private var tooltipTimer: DispatchWorkItem?

    /// How long the pointer rests on a tile before its tooltip shows.
    static let tooltipDelay: TimeInterval = 0.5
    /// The selection when the button went down: resizing and moving work from it.
    private var pressedSelection = CGRect.zero

    /// A press that moves less than this many points is a click, not a drag.
    static let dragThreshold: CGFloat = 3

    init(displays: [FrozenDisplay], windows: [OnScreenWindow], pointer: CGPoint, mode: AreaOverlayMode = .area) {
        self.displays = displays
        self.mode = mode
        self.windows = windows
        self.pointer = pointer
    }

    // MARK: Showing and tearing down

    /// Puts a panel on every display. `takesFocus` is false in a scripted run, which never
    /// activates snapit or takes the keyboard from what the user is doing.
    /// In `.pickColor` mode the overlay opens in the Color picker (the menu item and its Shortcut).
    func show(takesFocus: Bool) {
        activeIndex = displays.firstIndex { NSMouseInRect(pointer, $0.frame, false) } ?? 0
        let active = displays[activeIndex]
        cursor = AreaGeometry.clamp(
            CGPoint(x: pointer.x - active.frame.minX, y: active.frame.maxY - pointer.y), to: active.bounds)
        if mode == .pickColor {
            state = .pickingColor
            picker = makePickerSession(origin: .entry)
        }

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
            // A window Capture takes its picture live, after the overlay is gone: activating snapit
            // would turn the user's app inactive (grey traffic lights, dimmed toolbars, panels that
            // hide on deactivate dropping off the window list). The panel is non-activating, so it
            // takes the keys (Esc) without it.
            if mode != .window { NSApp.activate() }
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
        tooltipTimer?.cancel()
        tooltipTimer = nil
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
        aimPicker()
        refreshHover()
        setHoveredTile(tile(at: cursor, on: index))
        updateCursor()
        refreshScenes()
    }

    func mouseDown(_ index: Int, _ point: CGPoint, clickCount: Int = 1) {
        guard !isFinished else { return }
        setCursor(index, point)
        setHoveredTile(nil)
        if state == .pickingColor {
            pressInPicker(index, clickCount: clickCount)
            return
        }
        if mode == .window {
            isPressed = true
            pressedIndex = index
            refreshHover()
            refreshScenes()
            return
        }
        // A press on the Action bar is the bar's: on a tile it is that tile's, on its padding nothing.
        if let frame = containers[index].actionBarFrame, frame.contains(cursor) {
            isPressed = true
            hasMovedPastThreshold = false
            pressedIndex = index
            gesture = .bar
            pressedTile = tile(at: cursor, on: index)
            pressedTile?.isPressed = true
            pressedTile?.pointerDown(at: tilePoint(cursor, in: pressedTile, on: index))
            updateCursor()
            return
        }
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
        if mode == .window {
            // A press in the window overlay picks the window under the pointer where it lets go.
            refreshHover()
            refreshScenes()
            return
        }
        if case .bar = gesture {
            if let pressedTile { pressedTile.pointerDragged(at: tilePoint(clamped, in: pressedTile, on: index)) }
            return
        }
        if case .pick = gesture {
            aimPicker()
            refreshScenes()
            return
        }
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
        case .none, .bar, .pick: break
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
        if case .pick = ended {
            aimPicker()
            pickColor()
            return
        }
        if mode == .window {
            // A click on a highlighted window captures exactly that window; on empty desktop it
            // does nothing and the overlay carries on.
            refreshHover()
            if let window = hoveredOnScreenWindow {
                finish(with: .window(window))
            } else {
                refreshScenes()
            }
            return
        }
        if case .bar = ended, let tile = pressedTile {
            pressedTile = nil
            tile.isPressed = false
            let point = tilePoint(cursor, in: tile, on: index)
            tile.pointerUp(at: point, inside: CGRect(origin: .zero, size: tile.frame.size).contains(point))
        } else if case .newArea = ended {
            if hasMovedPastThreshold {
                if let selection, let selectionIndex { select(selection, on: selectionIndex) }
            } else if state == .hoverWindow, let hoveredWindow {
                select(hoveredWindow, on: activeIndex)
            }
            // (A plain click away from an adjusted selection changes nothing; a drag away made a
            // new one above.)
        }
        pressedTile = nil
        guard !isFinished else { return }
        updateCursor()
        refreshScenes()
    }

    private func setCursor(_ index: Int, _ point: CGPoint) {
        activeIndex = index
        cursor = AreaGeometry.clamp(point, to: displays[index].bounds)
    }

    // MARK: The Action bar

    /// The tile of the Action bar at `point` of display `index`.
    private func tile(at point: CGPoint, on index: Int) -> ActionBarControl? {
        guard let frame = containers[index].actionBarFrame, frame.contains(point) else { return nil }
        return containers[index].actionBar?.control(at: CGPoint(x: point.x - frame.minX, y: point.y - frame.minY))
    }

    /// `point` of display `index` in `tile`'s own space.
    private func tilePoint(_ point: CGPoint, in tile: ActionBarControl?, on index: Int) -> CGPoint {
        guard let tile, let frame = containers[index].actionBarFrame else { return .zero }
        return CGPoint(x: point.x - frame.minX - tile.frame.minX, y: point.y - frame.minY - tile.frame.minY)
    }

    /// Lights the tile under the pointer, and shows its tooltip once the pointer has rested on it.
    /// The delay is one shot, cancelled when the pointer moves to another tile or off the bar.
    private func setHoveredTile(_ tile: ActionBarControl?) {
        guard tile !== hoveredTile else { return }
        tooltipTimer?.cancel()
        tooltipTimer = nil
        tooltip = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hoveredTile?.isHovered = false
        tile?.isHovered = true
        CATransaction.commit()
        hoveredTile = tile
        guard let tile else { return }
        let timer = DispatchWorkItem { [weak self, weak tile] in
            guard let self, let tile, !self.isFinished, self.hoveredTile === tile else { return }
            self.tooltip = tile.tooltip
            self.refreshScenes()
        }
        tooltipTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tooltipDelay, execute: timer)
    }

    /// The window under the pointer, from the list read when the Shortcut fired.
    private func refreshHover() {
        guard state == .idle || state == .hoverWindow else { return }
        let display = displays[activeIndex]
        hoveredWindow = nil
        hoveredOnScreenWindow = nil
        for window in windows {
            let local = window.frame.offsetBy(dx: -display.cgOrigin.x, dy: -display.cgOrigin.y)
            if local.contains(cursor) {
                hoveredWindow = local.intersection(display.bounds)
                hoveredOnScreenWindow = window
                break
            }
        }
        state = hoveredWindow == nil ? .idle : .hoverWindow
    }

    /// The cursor: crosshair to select with, a resize cursor over a handle, a hand inside the
    /// selection, an arrow over the Action bar.
    func updateCursor() {
        guard !TestMode.isActive else { return }
        if mode == .window {
            NSCursor.arrow.set()
            return
        }
        if case .bar = gesture {
            NSCursor.arrow.set()
            return
        }
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
            if state == .pickingColor { escapePicker() } else { cancel() }
        case 36, 76:
            if state == .pickingColor { pickColor() } else if state == .adjusting { captureSelection() }
        case 123, 124, 125, 126:
            // Left, right, down, up: nudge the sampled pixel (Shift: ten at a time).
            if state == .pickingColor {
                let step = event.modifierFlags.contains(.shift) ? 10 : 1
                nudgePicker(
                    dx: event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0,
                    dy: event.keyCode == 126 ? -step : event.keyCode == 125 ? step : 0)
            }
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

    // MARK: Color picker

    /// Opens the Color picker from the Action bar (its button, or P). The selection stays where it
    /// was; Esc comes back to it.
    func beginPickingColor() {
        guard state == .adjusting, !isFinished else { return }
        setHoveredTile(nil)
        state = .pickingColor
        picker = makePickerSession(origin: .actionBar)
        updateCursor()
        refreshScenes()
    }

    private func makePickerSession(origin: ColorPickerSession.Origin) -> ColorPickerSession {
        let display = displays[activeIndex]
        return ColorPickerSession(
            origin: origin, cursor: cursor, displayIndex: activeIndex, scale: display.scale,
            width: display.image.width, height: display.image.height)
    }

    /// The pixel under the pointer is the sampled one.
    private func aimPicker() {
        guard state == .pickingColor else { return }
        let display = displays[activeIndex]
        picker?.aim(
            at: cursor, on: activeIndex, scale: display.scale, width: display.image.width, height: display.image.height)
    }

    /// A press in the picker picks when it is let go, wherever the pointer has been dragged to. The
    /// second click of a double-click on the Pick Color button is that button's, not a pick.
    private func pressInPicker(_ index: Int, clickCount: Int) {
        isPressed = true
        hasMovedPastThreshold = false
        pressedIndex = index
        if picker?.isTailOfOpeningClick(clickCount: clickCount) == true {
            gesture = .none
            return
        }
        gesture = .pick
        aimPicker()
        refreshScenes()
    }

    private func nudgePicker(dx: Int, dy: Int) {
        guard let index = picker?.displayIndex else { return }
        let image = displays[index].image
        picker?.nudge(dx: dx, dy: dy, width: image.width, height: image.height)
        refreshScenes()
    }

    /// Esc: back to the Action bar when the picker came from it, else the overlay ends.
    private func escapePicker() {
        guard let picker else { return }
        switch picker.origin {
        case .actionBar:
            self.picker = nil
            state = .adjusting
            isPressed = false
            gesture = .none
            updateCursor()
            refreshScenes()
        case .entry:
            cancel()
        }
    }

    /// Click or Enter: the sampled pixel's hex goes to the flow, which copies it and shows the toast.
    private func pickColor() {
        guard state == .pickingColor, let picker,
            let color = PixelSampler.color(in: displays[picker.displayIndex].image, at: picker.pixel)
        else { return }
        finish(with: .pickColor(PickedColor(hex: color.hex, displayIndex: picker.displayIndex)))
    }

    /// The picker's loupe on the display being sampled; every other layer of the overlay is hidden.
    private func refreshPickerScenes() {
        for (index, container) in containers.enumerated() {
            container.hideActionBar()
            var picked: PickerSceneState?
            if let picker, picker.displayIndex == index,
                let color = PixelSampler.color(in: displays[index].image, at: picker.pixel)
            {
                picked = PickerSceneState(pixel: picker.pixel, color: color, cursor: cursor)
            }
            container.sceneView.scene.update(
                AreaSceneState(
                    hasPointer: false, cursor: .zero, hoveredWindow: nil, selection: nil, actionBar: nil,
                    tooltip: nil, picker: picked))
        }
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
        if state == .pickingColor {
            refreshPickerScenes()
            return
        }
        let adjusting = state == .adjusting
        var resizing = false
        if case .resize = gesture { resizing = true }
        for (index, container) in containers.enumerated() {
            let showsSelection = index == selectionIndex
            var bar: CGRect?
            if adjusting, showsSelection, let selection {
                bar = container.showActionBar(for: selection, host: self, scale: CGFloat(displays[index].scale))
            } else {
                container.hideActionBar()
            }
            var tip: AreaTooltip?
            if let tooltip, let bar, let tile = hoveredTile {
                tip = AreaTooltip(text: tooltip, anchor: tile.frame.offsetBy(dx: bar.minX, dy: bar.minY))
            }
            // An adjusted Area has no crosshair or loupe, except while a handle is dragged (for
            // the exact pixel), so a pointer move changes nothing.
            let pointing = (!adjusting || resizing) && mode == .area
            container.sceneView.scene.update(
                AreaSceneState(
                    hasPointer: index == activeIndex && pointing, cursor: pointing ? cursor : .zero,
                    hoveredWindow: index == activeIndex ? hoveredWindow : nil,
                    selection: showsSelection ? selection : nil, showsHandles: adjusting && showsSelection,
                    actionBar: bar, tooltip: tip))
        }
    }
}
