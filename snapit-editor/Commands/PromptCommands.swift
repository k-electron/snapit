import AppKit

nonisolated extension SocketCommand {
    /// `editor-prompt`: `none`, or `shown <close|quit> editor=<N> title=<title> message=<message>
    /// buttons=<Cancel,Discard> escape=<title> command-d=<title> tooltips=<tooltip>|<tooltip>`: the question an Editor
    /// is waiting on. Test mode only.
    static let editorPrompt = SocketCommand("editor-prompt")
    /// `editor-prompt-answer discard|cancel|escape|command-d`: answers the prompt on screen: a button
    /// is pressed as a click does, Esc and ⌘D reach the sheet as key events. Replies `ok`, or
    /// `none` when no prompt shows. Test mode only.
    static let editorPromptAnswer = SocketCommand("editor-prompt-answer")
    /// `editor-drop <N> begin|taken|refused`: `begin` does what pressing the mouse on the thumbnail does
    /// (the drag's file is made from the Capture as it is now); `taken` or `refused` ends the drag
    /// session as the system does when a drop was taken (an Export) or nobody took it. Test mode only.
    static let editorDrop = SocketCommand("editor-drop")
    /// `export-hold on|off`: holds every Copy and Save after it took its snapshot, until released, so
    /// the Capture can be edited while an Export is still running. Test mode only.
    static let exportHold = SocketCommand("export-hold")
    /// `editor-first-mouse <N> item <id>`: the view under the centre of a toolbar item's control:
    /// `hit=<class> accepts-first-mouse=yes|no`, or `hit=none` when nothing is there. Test mode only.
    static let editorFirstMouse = SocketCommand("editor-first-mouse")
}

extension SocketCommandRegistry {
    /// The Quit prompt: asked when the menu bar app is about to quit (`confirm-quit`) and when the
    /// helper's own "Quit snapit" is chosen (`HelperDelegate`).
    func registerPromptCommands() {
        QuitPreparation.confirmations.append { await EditorSessions.shared.confirmQuit() }
        register(.confirmQuit) { _ in
            await QuitPreparation.confirm() ? "ok" : "cancel"
        }
        registerPromptTestCommands()
    }

    private func registerPromptTestCommands() {
        guard TestMode.isActive else { return }
        register(.editorPrompt) { _ in
            guard let shown = EditorPrompts.shared.current else { return "none" }
            let alert = shown.alert
            let number = shown.session.document?.captureNumber ?? 0
            let buttons = alert.buttons
            let escapeTitle = buttons.first { $0.keyEquivalent == "\u{1B}" }?.title ?? "none"
            let discardKey = buttons.first { $0.keyEquivalent == "d" && $0.keyEquivalentModifierMask == .command }?.title ?? "none"
            return "shown \(shown.kind.name) editor=\(number) title=\(alert.messageText) message=\(alert.informativeText) "
                + "buttons=\(buttons.map(\.title).joined(separator: ",")) escape=\(escapeTitle) command-d=\(discardKey) "
                + "tooltips=\(buttons.map { $0.toolTip ?? "" }.joined(separator: "|"))"
        }
        register(.editorPromptAnswer) { request in
            guard let shown = EditorPrompts.shared.current else { return "none" }
            switch request.arguments.first {
            case "discard": EditorPrompts.shared.answer(discard: true)
            case "cancel": EditorPrompts.shared.answer(discard: false)
            case "escape": Self.sendKey("\u{1B}", code: 53, flags: [], to: shown.alert.window)
            case "command-d": Self.sendKey("d", code: 2, flags: .command, to: shown.alert.window)
            default: return "error editor-prompt-answer discard|cancel|escape|command-d"
            }
            return "ok"
        }
        register(.exportHold) { request in
            guard let mode = request.arguments.first, ["on", "off"].contains(mode) else { return "error export-hold on|off" }
            ExportTestGate.shared.setHeld(mode == "on")
            return "ok"
        }
        register(.editorFirstMouse) { request in
            guard request.arguments.count == 3, request.arguments[1] == "item",
                let number = request.arguments.first.flatMap(Int.init),
                let session = EditorSessions.shared.session(captureNumber: number), let window = session.window,
                let tooltip = ToolbarRegistry.item(id: request.arguments[2])?.tooltip,
                let control = Self.controls(in: window).first(where: { $0.tooltip == tooltip }),
                let frameView = window.contentView?.superview
            else { return "error editor-first-mouse <N> item <id>" }
            guard let hit = frameView.hitTest(frameView.convert(control.center, from: nil)) else { return "hit=none" }
            return "hit=\(type(of: hit)) accepts-first-mouse=\(hit.acceptsFirstMouse(for: nil) ? "yes" : "no")"
        }
        register(.editorDrop) { request in
            guard let number = request.arguments.first.flatMap(Int.init),
                let session = EditorSessions.shared.session(captureNumber: number),
                let view = Self.dragOutView(in: session), request.arguments.count == 2
            else { return "error editor-drop <N> begin|taken|refused" }
            switch request.arguments[1] {
            case "begin": view.beginPendingFile()
            case "taken": view.finishDrag(operation: .copy)
            case "refused": view.finishDrag(operation: [])
            default: return "error editor-drop <N> begin|taken|refused"
            }
            return "ok"
        }
    }

    private static func dragOutView(in session: EditorSession) -> DragOutView? {
        func find(_ view: NSView) -> DragOutView? {
            if let match = view as? DragOutView { return match }
            for child in view.subviews { if let match = find(child) { return match } }
            return nil
        }
        return session.window?.contentView.flatMap(find)
    }

    /// A key event as the sheet's window receives it: key equivalents first, then the key itself
    /// (Esc reaches Cancel through the window).
    private static func sendKey(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags, to window: NSWindow) {
        guard
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
        else { return }
        if !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
    }
}
