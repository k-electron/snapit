import AppKit

nonisolated extension SocketCommand {
    /// `editor-mouse <N> down|drag|up <x> <y>`: a pointer event on Editor N's canvas at a point of
    /// the Capture (image points, origin at the top left). The point is mapped through the canvas's
    /// layers (where the Annotation layer really is on screen), and the event goes through the
    /// window's `sendEvent`, as a click does. Test mode only.
    static let editorMouse = SocketCommand("editor-mouse")
    /// `editor-drag <N> <x1> <y1> <x2> <y2>`: press, drag in steps, release. Test mode only.
    static let editorDrag = SocketCommand("editor-drag")
    /// `editor-keystroke <N> undo|redo|delete|enter|<character>`: sends Editor N's window ⌘Z, ⇧⌘Z, ⌫ or
    /// the key itself (a tool's key), the way a key press arrives. A `caps-` prefix holds Caps Lock
    /// down; a `plain-` prefix hands the window the key press only, without first offering it as a
    /// key equivalent. Test mode only.
    static let editorKeystroke = SocketCommand("editor-keystroke")
    /// `editor-style <N> fill outline|solid`, `width <points>` or `color <RRGGBB>`: what the style
    /// controls do. Test mode only.
    static let editorStyle = SocketCommand("editor-style")
    /// `editor-document <N>`: the Annotations (`annotation <id> <kind> <x1> <y1> <x2> <y2> <RRGGBB>
    /// <width> outline|solid`), the selection, the Undo and Redo steps and the revision. Test mode only.
    static let editorDocument = SocketCommand("editor-document")
    /// `editor-controls <N>`: one line per control in Editor N's toolbars, `control <tooltip> <x> <y>`:
    /// its tooltip and its centre in window coordinates, found through the accessibility tree.
    /// Test mode only.
    static let editorControls = SocketCommand("editor-controls")
    /// `editor-background <N>`: makes another Editor's window the key window, so Editor N is a
    /// background Editor. Replies `ok key=yes|no` (whether N is still key). Test mode only.
    static let editorBackground = SocketCommand("editor-background")
    /// `editor-click <N> tool <id>`, `item <id>` or `canvas <x> <y>`: a left click (press and release,
    /// through the window's `sendEvent`) on a rail button, a toolbar item or a point of the Capture.
    /// Replies `ok key-before=yes|no key-after=yes|no`. Test mode only.
    static let editorClick = SocketCommand("editor-click")
    /// `editor-preview <N> [overlay]`: renders the canvas's own layers (the Capture and the Annotations, no
    /// selection; `overlay` adds the selection's outline and handles and the crop rectangle's shade and handles) at the pixel size of what the canvas shows (the Capture, or what an applied crop keeps) with Core Animation, writes the PNG into the run's
    /// `probe` folder and replies `ok <path>`. The run compares it with the Export. Test mode only.
    static let editorPreview = SocketCommand("editor-preview")
    /// `editor-enabled <N> <item id>`: `yes` or `no`, whether the toolbar item is enabled now. Test mode only.
    static let editorEnabled = SocketCommand("editor-enabled")
    /// `editor-inject-effect <N> <x1> <y1> <x2> <y2>`: adds an Annotation of a test kind that Export
    /// does not draw in the Annotations stage (as Redaction will not), a solid green box, at the end of
    /// the document. Checks that such kinds lie beneath the others in the canvas and in hit testing.
    /// Test mode only.
    static let editorInjectEffect = SocketCommand("editor-inject-effect")
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
            var name = request.arguments[1]
            var extra: NSEvent.ModifierFlags = []
            var offerAsKeyEquivalent = true
            while true {
                if name.hasPrefix("caps-") {
                    extra.insert(.capsLock)
                    name.removeFirst("caps-".count)
                } else if name.hasPrefix("plain-") {
                    offerAsKeyEquivalent = false
                    name.removeFirst("plain-".count)
                } else {
                    break
                }
            }
            let event: NSEvent?
            switch name {
            case "undo": event = Self.keyEvent("z", code: 6, flags: extra.union(.command), window: window)
            case "redo": event = Self.keyEvent("z", code: 6, flags: extra.union([.command, .shift]), window: window)
            case "delete": event = Self.keyEvent("\u{7F}", code: 51, flags: extra, window: window)
            case "enter": event = Self.keyEvent("\r", code: 36, flags: extra, window: window)
            default:
                guard name.count == 1 else { return "error unknown key \(name)" }
                event = Self.keyEvent(name, code: 0, flags: extra, window: window)
            }
            return Self.send(event, to: window, offerAsKeyEquivalent: offerAsKeyEquivalent)
                ? "ok" : "error the window did not take the key"
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
        register(.editorEnabled) { request in
            guard let session = Self.session(request.arguments), request.arguments.count == 2,
                let item = ToolbarRegistry.item(id: request.arguments[1])
            else { return "error editor-enabled <N> <item id>" }
            return item.isEnabled(in: session) ? "yes" : "no"
        }
        register(.editorInjectEffect) { request in
            let numbers = request.arguments.dropFirst().compactMap(Double.init)
            guard let session = Self.session(request.arguments), let document = session.document, numbers.count == 4
            else { return "error editor-inject-effect <N> <x1> <y1> <x2> <y2>" }
            if AnnotationKinds.testKinds.isEmpty { AnnotationKinds.testKinds = [TestEffectAnnotationKind()] }
            document.edit { history in
                let id = history.makeID()
                history.change {
                    $0.annotations.append(
                        Annotation(
                            id: id, kind: TestEffectAnnotationKind.kindID, start: CGPoint(x: numbers[0], y: numbers[1]),
                            end: CGPoint(x: numbers[2], y: numbers[3]), style: AnnotationStyle()))
                }
            }
            return "ok"
        }
        register(.editorControls) { request in
            guard let session = Self.session(request.arguments), let window = session.window
            else { return "error no Editor \(request.arguments.first ?? "")" }
            return Self.controls(in: window).map { "control \($0.tooltip) \(Int($0.center.x)) \(Int($0.center.y))" }
                .joined(separator: "\n")
        }
        register(.editorBackground) { request in
            guard let session = Self.session(request.arguments), let window = session.window
            else { return "error no Editor \(request.arguments.first ?? "")" }
            if let other = EditorSessions.shared.sessions.values.first(where: { $0 !== session })?.window {
                other.makeKeyAndOrderFront(nil)
            }
            return "ok key=\(window.isKeyWindow ? "yes" : "no")"
        }
        register(.editorClick) { request in
            let arguments = request.arguments
            guard let session = Self.session(arguments), let window = session.window, arguments.count >= 3 else {
                return "error editor-click <N> tool <id> | item <id> | canvas <x> <y>"
            }
            let target: CGPoint
            switch arguments[1] {
            case "tool", "item":
                let tooltip = arguments[1] == "tool"
                    ? ToolRegistry.tool(id: arguments[2])?.tooltip : ToolbarRegistry.item(id: arguments[2])?.tooltip
                guard let tooltip else { return "error no \(arguments[1]) \(arguments[2])" }
                guard let control = Self.controls(in: window).first(where: { $0.tooltip == tooltip }) else {
                    return "error no control with the tooltip \(tooltip)"
                }
                target = control.center
            case "canvas":
                guard arguments.count == 4, let x = Double(arguments[2]), let y = Double(arguments[3]),
                    let point = Self.windowPoint(forImagePoint: CGPoint(x: x, y: y), in: session)
                else { return "error editor-click <N> canvas <x> <y>" }
                target = point
            default:
                return "error unknown target \(arguments[1])"
            }
            let before = window.isKeyWindow
            Self.deliver(.down, at: target, in: window)
            Self.deliver(.up, at: target, in: window)
            return "ok key-before=\(before ? "yes" : "no") key-after=\(window.isKeyWindow ? "yes" : "no")"
        }
        register(.editorPreview) { request in
            guard let session = Self.session(request.arguments), let document = session.document,
                let canvas = session.canvas, let folder = TestMode.folder("probe")
            else { return "error editor-preview <N>" }
            do {
                let withOverlay = request.arguments.dropFirst().first == "overlay"
                let png = try Self.renderPreview(of: canvas, capture: document.capture, withSelection: withOverlay)
                let url = folder.appendingPathComponent("preview.png")
                try png.write(to: url)
                return "ok \(url.path)"
            } catch {
                return "error \(error)"
            }
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

    /// Where a point of the Capture is in the window, found by asking the layer tree (the
    /// Annotation layer's own coordinates, flipped and scaled by the canvas) rather than the
    /// canvas's own arithmetic.
    private static func windowPoint(forImagePoint imagePoint: CGPoint, in session: EditorSession) -> CGPoint? {
        guard let canvas = session.canvas, let root = canvas.layer else { return nil }
        let inView = root.convert(imagePoint, from: canvas.annotationLayer)
        return canvas.convert(inView, to: nil)
    }

    /// Hands the window a mouse event at a point of the window, as AppKit would on a click.
    private static func deliver(_ phase: Phase, at windowPoint: CGPoint, in window: NSWindow) {
        let type: NSEvent.EventType = switch phase {
        case .down: .leftMouseDown
        case .drag: .leftMouseDragged
        case .up: .leftMouseUp
        }
        guard
            let event = NSEvent.mouseEvent(
                with: type, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: phase == .up ? 0 : 1)
        else { return }
        window.sendEvent(event)
    }

    private static func pointer(_ phase: Phase, at imagePoint: CGPoint, in session: EditorSession) -> Bool {
        guard let window = session.window, let point = windowPoint(forImagePoint: imagePoint, in: session) else { return false }
        deliver(phase, at: point, in: window)
        return true
    }

    /// The controls of the window's toolbars: tooltip and centre in window coordinates, from the
    /// marker views test mode puts behind each control (`ControlMarker`).
    private static func controls(in window: NSWindow) -> [(tooltip: String, center: CGPoint)] {
        var found: [(tooltip: String, center: CGPoint)] = []
        func visit(_ view: NSView) {
            if let marker = view as? ControlMarkerView {
                let frame = marker.convert(marker.bounds, to: nil)
                found.append((marker.tooltip, CGPoint(x: frame.midX, y: frame.midY)))
            }
            for child in view.subviews { visit(child) }
        }
        if let content = window.contentView { visit(content) }
        return found
    }

    /// The canvas's layers rendered at the pixel size of what the canvas shows (the Capture, or the
    /// part an applied crop keeps), as a PNG in the Capture's color space.
    private static func renderPreview(of canvas: CanvasView, capture: OpenedCapture, withSelection: Bool = false) throws -> Data {
        let width = canvas.cropPixels?.width ?? capture.info.width
        let height = canvas.cropPixels?.height ?? capture.info.height
        let target = try capture.pixels.makeEmptyBuffer(width: width, height: height)
        try target.withCGContext { context in
            context.scaleBy(x: capture.info.scale, y: capture.info.scale)
            let wasHidden = canvas.selectionLayer.isHidden
            canvas.selectionLayer.isHidden = !withSelection
            canvas.contentLayer.render(in: context)
            canvas.selectionLayer.isHidden = wasHidden
        }
        return try target.encodePNG(level: .fast, dpi: capture.info.dpi)
    }

    private static func keyEvent(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags, window: NSWindow) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
    }

    /// Key equivalents first (the window, then the main menu), then the key itself to the window.
    private static func send(_ event: NSEvent?, to window: NSWindow, offerAsKeyEquivalent: Bool = true) -> Bool {
        guard let event else { return false }
        if offerAsKeyEquivalent {
            if window.performKeyEquivalent(with: event) { return true }
            if NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return true }
        }
        window.sendEvent(event)
        return true
    }
}

/// A kind that, like Redaction, is not drawn by `AnnotationStage`: a solid green box in the preview.
nonisolated struct TestEffectAnnotationKind: AnnotationKind {
    static let kindID = AnnotationKindID("test-effect")
    let id = TestEffectAnnotationKind.kindID
    let drawnByAnnotationStage = false

    func paint(for annotation: Annotation) -> AnnotationPaint {
        AnnotationPaint(
            path: CGPath(rect: annotation.box, transform: nil), fill: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
    }
}
