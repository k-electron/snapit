import AppKit

/// A key press as a Shortcut recorder receives it, for the scripted run: sent through the
/// application's event dispatch to a window, so the recorder's own event monitor sees it.
@MainActor
enum RecorderKeyEvent {
    static let usage = "<key code> [<modifier>,...]"

    /// Sends the key described by `arguments` (`<key code> [<modifier>,...]`) to `window`, then
    /// waits for the menu bar app to have been told. Returns `ok` or `error …`.
    static func send(_ arguments: [String], to window: NSWindow, model: SettingsModel) async -> String {
        guard let combo = ShortcutCombo.parse(wire: arguments), let combo else { return "error key \(usage)" }
        var flags: NSEvent.ModifierFlags = []
        flags.formUnion(combo.modifiers)
        guard
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: UInt16(combo.keyCode))
        else { return "error could not make the key event" }
        NSApp.sendEvent(event)
        await model.applying?.value
        return "ok"
    }
}
