import AppKit
import Carbon.HIToolbox

/// Listens for the keys of one Shortcut being recorded: a local event monitor that exists only
/// while a recorder is waiting (nothing runs at rest). It swallows every key meanwhile, so the
/// menu's own key equivalents (⌘, and ⌘Q) cannot fire in the middle of a recording.
///
/// KeyboardShortcuts' own recorder is not used here: it keeps its choice in this process's
/// `UserDefaults.standard`, but only the menu bar app's counts. See docs/development/testing.md.
@MainActor
final class ShortcutRecorder {
    enum Result: Equatable {
        /// Esc: leave the Shortcut as it was.
        case cancel
        /// Delete: unassign the Shortcut.
        case clear
        case accept(ShortcutCombo)
        /// Not a key combination a global Shortcut may take; the text says what to press instead.
        case rejected(String)
    }

    private var monitor: Any?

    func start(_ handler: @escaping @MainActor (Result) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // A key held down repeats; only the first press counts.
            guard !event.isARepeat else { return nil }
            let result = Self.interpret(keyCode: Int(event.keyCode), flags: event.modifierFlags)
            MainActor.assumeIsolated { handler(result) }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// What a key press means to a recorder. A global Shortcut takes its keys from every app, so
    /// the ones typing and the editing commands depend on are refused: ⌘ alone with a letter or
    /// number (⌘C, ⌘V, ⌘Q, ⌘W, ⌘Z), and ⌥ or ⌥⇧ alone with a printable key (they type å or é on many
    /// layouts). A Shortcut has ⌃, or ⌘ with another modifier, or is a function key.
    static func interpret(keyCode: Int, flags: NSEvent.ModifierFlags) -> Result {
        let modifiers = flags.intersection([.control, .option, .shift, .command])
        if modifiers.isEmpty {
            if keyCode == kVK_Escape { return .cancel }
            if keyCode == kVK_Delete || keyCode == kVK_ForwardDelete { return .clear }
        }
        if ShortcutCombo.isFunctionKey(keyCode) { return .accept(ShortcutCombo(keyCode: keyCode, modifiers: modifiers)) }
        let hasControl = modifiers.contains(.control)
        let commandWithAnother = modifiers.contains(.command) && !modifiers.subtracting(.command).isEmpty
        guard hasControl || commandWithAnother else {
            return .rejected("Hold ⌃, or ⌘ with ⌥ or ⇧, as well. A key combination like this one is used by every app.")
        }
        return .accept(ShortcutCombo(keyCode: keyCode, modifiers: modifiers))
    }
}
