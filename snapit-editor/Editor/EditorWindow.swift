import AppKit

/// The Editor window: always able to become key, and handles the keys that belong to the
/// Editor itself before the menu bar does (⌘C, ⌘W, Esc, a tool's key).
final class EditorWindow: NSWindow {
    weak var session: EditorSession?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command, let session, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "c": session.startCopy()
        case "w": session.close()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard let session else { return super.keyDown(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 {  // Esc
            session.escape()
        } else if flags.isEmpty, let key = event.charactersIgnoringModifiers?.first,
            let tool = ToolRegistry.tool(forKey: key)
        {
            session.selectTool(id: tool.id)
        } else {
            super.keyDown(with: event)
        }
    }
}
