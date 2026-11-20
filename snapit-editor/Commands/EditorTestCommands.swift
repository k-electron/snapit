import AppKit

nonisolated extension SocketCommand {
    /// Replies with the numbers of the open Editors, one per line. Test mode only.
    static let editors = SocketCommand("editors")
    /// `editor-facts <N>`: `key=value` lines about Editor N: the Capture's pixel size, scale and
    /// resolution, the window, the canvas, the active tool, the app's activation policy. Test mode only.
    static let editorFacts = SocketCommand("editor-facts")
    /// `editor-key <N> copy|escape|close`: sends Editor N's window the key press (⌘C, Esc, ⌘W)
    /// as an event, and replies `ok` when what it does has finished. Test mode only.
    static let editorKey = SocketCommand("editor-key")
    /// `editor-press <N> <item id>`: runs a top toolbar item's action in Editor N, as pressing
    /// its button does, and replies `ok` when it has finished. Test mode only.
    static let editorPress = SocketCommand("editor-press")
    /// `editor-toolbar <N>`: one line per toolbar item and tool, `<kind> <id> <slot or order> <tooltip>`.
    /// Test mode only.
    static let editorToolbar = SocketCommand("editor-toolbar")
    /// Replies with the names of the Export pipeline's steps, in the order they run. Test mode only.
    static let exportStages = SocketCommand("export-stages")
}

extension SocketCommandRegistry {
    func registerEditorTestCommands() {
        guard TestMode.isActive else { return }

        register(.editors) { _ in
            EditorSessions.shared.captureNumbers.map(String.init).joined(separator: "\n")
        }
        register(.exportStages) { _ in
            ExportPipeline.stageIDs.joined(separator: "\n")
        }
        register(.editorFacts) { request in
            guard let session = Self.session(request) else { return "error no Editor \(request.arguments.first ?? "")" }
            return Self.facts(of: session).map { "\($0.0)=\($0.1)" }.joined(separator: "\n")
        }
        register(.editorToolbar) { request in
            guard Self.session(request) != nil else { return "error no Editor \(request.arguments.first ?? "")" }
            let tools = ToolRegistry.all.map { "tool \($0.id) \($0.order) \($0.tooltip)" }
            let items = ToolbarSlot.allCases.flatMap { slot in
                ToolbarRegistry.items(in: slot).map { "item \($0.id) \(slot.rawValue) \($0.tooltip)" }
            }
            return (tools + items).joined(separator: "\n")
        }
        register(.editorKey) { request in
            guard let session = Self.session(request), request.arguments.count >= 2 else {
                return "error editor-key <N> copy|escape|close"
            }
            guard let window = session.window else { return "error the Editor has no window" }
            let sent: Bool
            switch request.arguments[1] {
            case "copy": sent = Self.send(Self.keyEvent("c", code: 8, flags: .command, window: window), to: window)
            case "close": sent = Self.send(Self.keyEvent("w", code: 13, flags: .command, window: window), to: window)
            case "escape": sent = Self.send(Self.keyEvent("\u{1B}", code: 53, flags: [], window: window), to: window)
            default: return "error unknown key \(request.arguments[1])"
            }
            await session.copyTask?.value
            return sent ? "ok" : "error the window did not take the key"
        }
        register(.editorPress) { request in
            guard let session = Self.session(request), request.arguments.count >= 2 else {
                return "error editor-press <N> <item id>"
            }
            guard let item = ToolbarRegistry.item(id: request.arguments[1]) else {
                return "error no toolbar item \(request.arguments[1])"
            }
            guard item.isEnabled(in: session) else { return "error toolbar item is disabled" }
            item.perform(in: session)
            await session.copyTask?.value
            return "ok"
        }
    }

    private static func session(_ request: SocketRequest) -> EditorSession? {
        request.arguments.first.flatMap(Int.init).flatMap { EditorSessions.shared.session(captureNumber: $0) }
    }

    private static func facts(of session: EditorSession) -> [(String, String)] {
        let info = session.document.capture.info
        let window = session.window
        let canvas = session.canvas
        return [
            ("pixels", "\(info.width)x\(info.height)"),
            ("scale", "\(info.scale)"),
            ("dpi", "\(info.dpi)"),
            ("window", window.map { $0.isVisible ? "visible" : "hidden" } ?? "none"),
            ("window-title", window?.title ?? ""),
            ("canvas", canvas.map { $0.wantsLayer && $0.layer != nil ? "layer-hosted" : "plain" } ?? "none"),
            ("tool", session.selectedToolID),
            ("activation", NSApp.activationPolicy() == .regular ? "regular" : "accessory"),
            ("pid", "\(ProcessInfo.processInfo.processIdentifier)"),
        ]
    }

    private static func keyEvent(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags, window: NSWindow) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
    }

    /// Hands the event to the window the way a key press arrives: key equivalents first (the
    /// window, then the main menu), then the key itself to the first responder.
    private static func send(_ event: NSEvent?, to window: NSWindow) -> Bool {
        guard let event else { return false }
        if window.performKeyEquivalent(with: event) { return true }
        if NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return true }
        window.sendEvent(event)
        return true
    }
}
