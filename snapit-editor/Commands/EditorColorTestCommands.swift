import AppKit

nonisolated extension SocketCommand {
    /// `editor-color-panel <N> state | choose <RRGGBB> | drag <RRGGBB>... | drag-event <RRGGBB>...`: the
    /// color panel's fixture (test mode has no real panel). `state` replies `shown=yes|no color=RRGGBB`;
    /// `choose` is a value typed into the panel (the mouse button up); `drag` is a drag across the colors
    /// with the button down that ends without the app ever seeing the mouse-up (a control's own tracking
    /// loop); `drag-event` ends with a real mouse-up event. Test mode only.
    static let editorColorPanel = SocketCommand("editor-color-panel")
    /// `editor-eyedropper-cursor`: where the eyedropper cursor's glyph ends (the opaque pixel nearest the
    /// image's bottom left corner, found in the cursor image drawn at 1x and at 2x) and its hot spot, in
    /// points from the top left: `scale=1 tip=x,y hotspot=x,y`, then the same for 2x. Test mode only.
    static let editorEyedropperCursor = SocketCommand("editor-eyedropper-cursor")
    /// `editor-layout <N>`: `content-min-width=`, `content-width=` and `rightmost-control=` (the right edge
    /// of the last control of the top toolbar, in window points), so the run can see the toolbar fit.
    /// Test mode only.
    static let editorLayout = SocketCommand("editor-layout")
    /// `editor-control-enabled <N> <tooltip>`: `yes` or `no`, whether the control with that tooltip is
    /// enabled as the window shows it (what a user sees greyed out), not as the item's own state says.
    /// Test mode only.
    static let editorControlEnabled = SocketCommand("editor-control-enabled")
    /// `editor-key-command <N> <character>`: ⌘ and the character, as a key press (key equivalents
    /// first, then the key itself to the first responder). Test mode only.
    static let editorKeyCommand = SocketCommand("editor-key-command")
    /// `editor-become-key <N>`: tells Editor N's window delegate that its window became the key window.
    /// (An app that is not active, as in a scripted run, never has a key window, so the notification AppKit
    /// would send for the user clicking into that Editor is sent here.) Test mode only.
    static let editorBecomeKey = SocketCommand("editor-become-key")
}

extension SocketCommandRegistry {
    func registerEditorColorTestCommands() {
        guard TestMode.isActive else { return }

        register(.editorEyedropperCursor) { _ in
            let cursor = EyedropperCursor.shared
            return [1, 2].map { scale in
                let tip = EyedropperCursor.tip(of: cursor.image, scale: scale)
                let numbers = { (point: CGPoint?) in point.map { String(format: "%.2f,%.2f", $0.x, $0.y) } ?? "none" }
                return "scale=\(scale) tip=\(numbers(tip)) hotspot=\(numbers(cursor.hotSpot))"
            }.joined(separator: "\n")
        }
        register(.editorControlEnabled) { request in
            guard let session = Self.session(request.arguments), let window = session.window, request.arguments.count == 2,
                let content = window.contentView
            else { return "error editor-control-enabled <N> <tooltip>" }
            var found: Bool?
            func visit(_ view: NSView) {
                if let marker = view as? ControlMarkerView, marker.tooltip == request.arguments[1] {
                    found = marker.isControlEnabled
                }
                for child in view.subviews { visit(child) }
            }
            visit(content)
            return found.map { $0 ? "yes" : "no" } ?? "error no control with that tooltip"
        }
        register(.editorBecomeKey) { request in
            guard let session = Self.session(request.arguments), let window = session.window
            else { return "error editor-become-key <N>" }
            session.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
            return "ok"
        }
        register(.editorKeyCommand) { request in
            guard let session = Self.session(request.arguments), let window = session.window, request.arguments.count == 2,
                request.arguments[1].count == 1,
                let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: request.arguments[1],
                    charactersIgnoringModifiers: request.arguments[1], isARepeat: false, keyCode: 0)
            else { return "error editor-key-command <N> <character>" }
            if window.performKeyEquivalent(with: event) { return "ok" }
            if NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return "ok" }
            window.sendEvent(event)
            await session.copyTask?.value
            return "ok"
        }
        register(.editorLayout) { request in
            guard let session = Self.session(request.arguments), let window = session.window, let content = window.contentView
            else { return "error editor-layout <N>" }
            var frames: [(tooltip: String, frame: CGRect)] = []
            func visit(_ view: NSView) {
                if let marker = view as? ControlMarkerView { frames.append((marker.tooltip, marker.convert(marker.bounds, to: nil))) }
                for child in view.subviews { visit(child) }
            }
            visit(content)
            var overlapping = 0
            for (index, first) in frames.enumerated() {
                for second in frames[(index + 1)...] where first.frame.intersection(second.frame).width > 1
                    && first.frame.intersection(second.frame).height > 1
                {
                    overlapping += 1
                }
            }
            let rightmost = frames.map(\.frame.midX).max() ?? 0
            let red = frames.first { $0.tooltip == "Red" }?.frame.midY ?? 0
            let undo = frames.first { $0.tooltip.hasPrefix("Undo") }?.frame.midY ?? 0
            return [
                "content-min-width=\(Int(window.contentMinSize.width))", "content-width=\(Int(content.bounds.width))",
                "rightmost-control=\(Int(rightmost))", "overlapping-controls=\(overlapping)",
                "options-row=\(abs(red - undo) > 20 ? "second" : "same")",
            ].joined(separator: "\n")
        }
        register(.editorColorPanel) { request in
            let arguments = request.arguments
            let panel = FixtureColorPanel.shared
            // The panel's state does not need an Editor: it is what is left after the last one closes.
            if arguments.count >= 2, arguments[1] == "state" {
                let color = panel.color.usingColorSpace(.sRGB) ?? panel.color
                let hex = AnnotationColor(
                    red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent)).hex
                return "shown=\(panel.isShown ? "yes" : "no") color=\(hex)"
            }
            guard let session = Self.session(arguments), arguments.count >= 2, let window = session.window
            else { return "error editor-color-panel <N> state | choose <RRGGBB> | drag <RRGGBB>... | drag-event <RRGGBB>..." }
            switch arguments[1] {
            case "choose":
                guard arguments.count == 3, let color = AnnotationColor(hex: arguments[2]) else { return "error choose <RRGGBB>" }
                panel.isDragging = false
                panel.choose(NSColor(cgColor: color.cgColor) ?? .red)
                return "ok"
            case "drag", "drag-event":
                let colors = arguments.dropFirst(2).compactMap(AnnotationColor.init(hex:))
                guard !colors.isEmpty else { return "error drag <RRGGBB>..." }
                panel.isDragging = true
                for color in colors { panel.choose(NSColor(cgColor: color.cgColor) ?? .red) }
                panel.isDragging = false
                if arguments[1] == "drag" { return "ok" }
                guard
                    let up = NSEvent.mouseEvent(
                        with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
                else { return "error no mouse event" }
                NSApp.sendEvent(up)
                return "ok"
            default:
                return "error unknown subcommand \(arguments[1])"
            }
        }
    }
}
