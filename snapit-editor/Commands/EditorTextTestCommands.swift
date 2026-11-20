import AppKit

nonisolated extension SocketCommand {
    /// `editor-type <N> <text>`: types the characters into Editor N's window one key press each, as
    /// plain key events for the first responder (the text view, or the window when none takes them).
    /// `%0A` is Return. Test mode only.
    static let editorType = SocketCommand("editor-type")
    /// `editor-text <N>`: `editing=yes|no`, `picking=yes|no` and one line per Text,
    /// `text <id> <size> <x> <y> <width> <height> <text>` (the box in image points, the text with
    /// `%0A` for a new line). Test mode only.
    static let editorText = SocketCommand("editor-text")
    /// `editor-double-click <N> <x> <y>`: a click and a second click on the canvas at a point of the
    /// Capture, the second one with a click count of 2, through the window's `sendEvent`. Test mode only.
    static let editorDoubleClick = SocketCommand("editor-double-click")
    /// `editor-window-image <N> <name>`: Editor N's window content drawn into `<run>/probe/<name>.png`
    /// (for looking at the layout; replies `ok <path>`). Test mode only.
    static let editorWindowImage = SocketCommand("editor-window-image")
}

extension SocketCommandRegistry {
    func registerEditorTextTestCommands() {
        guard TestMode.isActive else { return }

        register(.editorType) { request in
            guard let session = Self.session(request.arguments), request.arguments.count == 2, let window = session.window
            else { return "error editor-type <N> <text>" }
            for character in request.arguments[1] {
                let isReturn = character == "\n"
                guard
                    let event = NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, characters: isReturn ? "\r" : String(character),
                        charactersIgnoringModifiers: isReturn ? "\r" : String(character), isARepeat: false,
                        keyCode: isReturn ? 36 : 0)
                else { return "error no key event" }
                // A plain key is never a key equivalent (AppKit offers only ⌘ and ⌃ keys to the menus first);
                // the main menu's own items (Emoji & Symbols is "e") would swallow letters here.
                window.sendEvent(event)
            }
            return "ok"
        }
        register(.editorWindowImage) { request in
            guard let session = Self.session(request.arguments), let view = session.window?.contentView,
                let folder = TestMode.folder("probe"), let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds),
                request.arguments.count == 2
            else { return "error editor-window-image <N> <name>" }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = folder.appendingPathComponent("\(request.arguments[1]).png")
            guard let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil
            else { return "error could not write the image" }
            return "ok \(url.path)"
        }
        register(.editorDoubleClick) { request in
            let numbers = request.arguments.dropFirst().compactMap(Double.init)
            guard let session = Self.session(request.arguments), let window = session.window, numbers.count == 2,
                let point = Self.windowPoint(forImagePoint: CGPoint(x: numbers[0], y: numbers[1]), in: session)
            else { return "error editor-double-click <N> <x> <y>" }
            for (type, count) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 1), (.leftMouseDown, 2), (.leftMouseUp, 2)] {
                guard
                    let event = NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count,
                        pressure: type == .leftMouseUp ? 0 : 1)
                else { return "error no mouse event" }
                window.sendEvent(event)
            }
            return "ok"
        }
        register(.editorText) { request in
            guard let session = Self.session(request.arguments), let document = session.document
            else { return "error no Editor \(request.arguments.first ?? "")" }
            var lines = [
                "editing=\(session.isEditingText ? "yes" : "no")",
                "picking=\(session.isPickingColor ? "yes" : "no")",
            ]
            for annotation in document.annotations where annotation.kind == .text {
                let box = TextAnnotationKind().bounds(of: annotation)
                let numbers = [box.minX, box.minY, box.width, box.height].map { String(format: "%.2f", $0) }.joined(separator: " ")
                let text = annotation.text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
                lines.append("text \(annotation.id) \(Int(annotation.style.textSize)) \(numbers) \(text)")
            }
            return lines.joined(separator: "\n")
        }
    }
}
