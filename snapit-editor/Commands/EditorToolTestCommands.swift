import AppKit

nonisolated extension SocketCommand {
    /// `editor-mouse <N> down|drag|up <x> <y>`: a pointer event on Editor N's canvas at a point of
    /// the Capture (image points, origin at the top left). The event goes through the canvas's
    /// own handlers, so the zoom mapping and the active tool are exercised. Test mode only.
    static let editorMouse = SocketCommand("editor-mouse")
    /// `editor-drag <N> <x1> <y1> <x2> <y2>`: press, drag in steps, release. Test mode only.
    static let editorDrag = SocketCommand("editor-drag")
    /// `editor-keystroke <N> undo|redo|delete|<character>`: sends Editor N's window ⌘Z, ⇧⌘Z, ⌫ or
    /// the key itself (a tool's key), the way a key press arrives. Test mode only.
    static let editorKeystroke = SocketCommand("editor-keystroke")
    /// `editor-style <N> fill outline|solid`, `width <points>` or `color <RRGGBB>`: what the style
    /// controls do. Test mode only.
    static let editorStyle = SocketCommand("editor-style")
    /// `editor-document <N>`: the Annotations (`annotation <id> <kind> <x1> <y1> <x2> <y2> <RRGGBB>
    /// <width> outline|solid`), the selection, the Undo and Redo steps and the revision. Test mode only.
    static let editorDocument = SocketCommand("editor-document")
    /// `editor-first-click <N>`: one line per control host in the window, `<name> yes|no`, whether
    /// the first click on a background Editor reaches it. Test mode only.
    static let editorFirstClick = SocketCommand("editor-first-click")
    /// `editor-menu-keys`: one line per item of the helper's Edit menu, `<title> key=<hex codes> modifiers=<mask>`:
    /// the key equivalent the menu shows for it. Test mode only.
    static let editorMenuKeys = SocketCommand("editor-menu-keys")
}

extension SocketCommandRegistry {
    func registerEditorToolTestCommands() {
        guard TestMode.isActive else { return }

        register(.editorMouse) { request in
            let arguments = request.arguments
            guard let session = Self.session(arguments), arguments.count == 4,
                let x = Double(arguments[2]), let y = Double(arguments[3])
            else { return "error editor-mouse <N> down|drag|up <x> <y>" }
            guard let phase = Self.phase(arguments[1]) else { return "error unknown phase \(arguments[1])" }
            return Self.pointer(phase, at: CGPoint(x: x, y: y), in: session) ? "ok" : "error the Editor has no canvas"
        }
        register(.editorDrag) { request in
            let numbers = request.arguments.dropFirst().compactMap(Double.init)
            guard let session = Self.session(request.arguments), numbers.count == 4 else {
                return "error editor-drag <N> <x1> <y1> <x2> <y2>"
            }
            let from = CGPoint(x: numbers[0], y: numbers[1])
            let to = CGPoint(x: numbers[2], y: numbers[3])
            var done = Self.pointer(.down, at: from, in: session)
            for step in 1...4 {
                let t = Double(step) / 5
                done = Self.pointer(.drag, at: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t), in: session) && done
            }
            done = Self.pointer(.up, at: to, in: session) && done
            return done ? "ok" : "error the Editor has no canvas"
        }
        register(.editorKeystroke) { request in
            guard let session = Self.session(request.arguments), request.arguments.count == 2, let window = session.window
            else { return "error editor-keystroke <N> undo|redo|delete|<character>" }
            let name = request.arguments[1]
            let event: NSEvent?
            switch name {
            case "undo": event = Self.keyEvent("z", code: 6, flags: .command, window: window)
            case "redo": event = Self.keyEvent("z", code: 6, flags: [.command, .shift], window: window)
            case "delete": event = Self.keyEvent("\u{7F}", code: 51, flags: [], window: window)
            default:
                guard name.count == 1 else { return "error unknown key \(name)" }
                event = Self.keyEvent(name, code: 0, flags: [], window: window)
            }
            return Self.send(event, to: window) ? "ok" : "error the window did not take the key"
        }
        register(.editorStyle) { request in
            let arguments = request.arguments
            guard let session = Self.session(arguments), arguments.count == 3 else {
                return "error editor-style <N> fill|width|color <value>"
            }
            switch arguments[1] {
            case "fill":
                guard ["outline", "solid"].contains(arguments[2]) else { return "error fill outline|solid" }
                session.setAnnotationFilled(arguments[2] == "solid")
            case "width":
                guard let width = Double(arguments[2]) else { return "error width <points>" }
                session.setAnnotationWidth(CGFloat(width))
            case "color":
                guard let color = AnnotationColor(hex: arguments[2]) else { return "error color <RRGGBB>" }
                session.setAnnotationColor(color)
            default:
                return "error unknown style \(arguments[1])"
            }
            return "ok"
        }
        register(.editorDocument) { request in
            guard let session = Self.session(request.arguments), let document = session.document
            else { return "error no Editor \(request.arguments.first ?? "")" }
            var lines = document.annotations.map { annotation in
                let numbers = [annotation.start.x, annotation.start.y, annotation.end.x, annotation.end.y]
                    .map { String(format: "%.1f", $0) }.joined(separator: " ")
                return "annotation \(annotation.id) \(annotation.kind.rawValue) \(numbers) \(annotation.style.color.hex) "
                    + "\(String(format: "%.1f", annotation.style.width)) \(annotation.style.filled ? "solid" : "outline")"
            }
            lines.append("selected=\(session.selectedAnnotationID.map(String.init) ?? "none")")
            lines.append("undo-steps=\(document.history.undoSteps.count)")
            lines.append("redo-steps=\(document.history.redoSteps.count)")
            lines.append("revision=\(document.revision)")
            lines.append("tool=\(session.selectedToolID)")
            lines.append("zoom=\(String(format: "%.3f", session.canvas?.zoom ?? 0))")
            return lines.joined(separator: "\n")
        }
        register(.editorMenuKeys) { _ in
            let edit = NSApp.mainMenu?.items.first { $0.title == EditorMenu.edit.rawValue }?.submenu
            return (edit?.items ?? []).filter { !$0.isSeparatorItem }.map { item in
                let codes = item.keyEquivalent.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: ",")
                return "\(item.title) key=\(codes.isEmpty ? "none" : codes) modifiers=\(item.keyEquivalentModifierMask.rawValue)"
            }.joined(separator: "\n")
        }
        register(.editorFirstClick) { request in
            guard let session = Self.session(request.arguments), let content = session.window?.contentView
            else { return "error no Editor \(request.arguments.first ?? "")" }
            return content.subviews.map { view in
                let name = String(describing: type(of: view)).split(separator: "<").first.map(String.init) ?? ""
                let content = String(describing: type(of: view)).split(separator: "<").dropFirst().first
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ">")) } ?? ""
                return "\(name)\(content.isEmpty ? "" : " " + content) \(view.acceptsFirstMouse(for: nil) ? "yes" : "no")"
            }.joined(separator: "\n")
        }
    }

    private enum Phase { case down, drag, up }

    private static func phase(_ name: String) -> Phase? {
        switch name {
        case "down": .down
        case "drag": .drag
        case "up": .up
        default: nil
        }
    }

    private static func session(_ arguments: [String]) -> EditorSession? {
        arguments.first.flatMap(Int.init).flatMap { EditorSessions.shared.session(captureNumber: $0) }
    }

    /// Hands the canvas the pointer event for a point of the Capture, as AppKit would on a click.
    private static func pointer(_ phase: Phase, at imagePoint: CGPoint, in session: EditorSession) -> Bool {
        guard let canvas = session.canvas, let window = session.window else { return false }
        let inWindow = canvas.convert(canvas.viewPoint(fromImagePoint: imagePoint), to: nil)
        let type: NSEvent.EventType = switch phase {
        case .down: .leftMouseDown
        case .drag: .leftMouseDragged
        case .up: .leftMouseUp
        }
        guard
            let event = NSEvent.mouseEvent(
                with: type, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: phase == .up ? 0 : 1)
        else { return false }
        switch phase {
        case .down: canvas.mouseDown(with: event)
        case .drag: canvas.mouseDragged(with: event)
        case .up: canvas.mouseUp(with: event)
        }
        return true
    }

    private static func keyEvent(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags, window: NSWindow) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
    }

    /// Key equivalents first (the window, then the main menu), then the key itself to the window.
    private static func send(_ event: NSEvent?, to window: NSWindow) -> Bool {
        guard let event else { return false }
        if window.performKeyEquivalent(with: event) { return true }
        if NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return true }
        window.sendEvent(event)
        return true
    }
}
