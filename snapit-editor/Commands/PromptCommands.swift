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
    /// `editor-drop <N> taken|refused`: ends the thumbnail's drag session as the system does when
    /// a drop was taken (an Export) or nobody took it. Test mode only.
    static let editorDrop = SocketCommand("editor-drop")
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
        register(.editorDrop) { request in
            guard let number = request.arguments.first.flatMap(Int.init),
                let session = EditorSessions.shared.session(captureNumber: number),
                let view = Self.dragOutView(in: session), request.arguments.count == 2
            else { return "error editor-drop <N> taken|refused" }
            switch request.arguments[1] {
            case "taken": view.finishDrag(operation: .copy)
            case "refused": view.finishDrag(operation: [])
            default: return "error editor-drop <N> taken|refused"
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
