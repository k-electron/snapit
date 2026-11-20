import AppKit

/// The Editor window: always able to become key. Its key equivalents come from
/// `ToolbarRegistry` (each item names its own key), tool keys from `ToolRegistry`, and Esc
/// closes the Editor.
final class EditorWindow: NSWindow {
    weak var session: EditorSession?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Text being edited takes its own keys first (⌘C copies its selection).
        if firstResponder is NSText, super.performKeyEquivalent(with: event) { return true }
        if let session, let item = ToolbarRegistry.item(matching: event), item.isEnabled(in: session) {
            item.perform(in: session)
            return true
        }
        return firstResponder is NSText ? false : super.performKeyEquivalent(with: event)
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

    /// The action of every menu item built from a toolbar item (`HelperMainMenu`): runs the
    /// item named by the menu item's `representedObject`.
    @objc func performToolbarItem(_ sender: NSMenuItem) {
        guard let session, let id = sender.representedObject as? String, let item = ToolbarRegistry.item(id: id)
        else { return }
        item.perform(in: session)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performToolbarItem(_:)) {
            guard let session, let id = menuItem.representedObject as? String, let item = ToolbarRegistry.item(id: id)
            else { return false }
            return item.isEnabled(in: session)
        }
        return super.validateMenuItem(menuItem)
    }
}
