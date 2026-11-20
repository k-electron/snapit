import AppKit
import Carbon.HIToolbox

/// Listens for the keys of one Shortcut being recorded: a local event monitor that exists only
/// while a recorder is waiting (nothing runs at rest). It swallows every key meanwhile, so the
/// menu's own key equivalents (⌘, and ⌘Q) cannot fire in the middle of a recording.
///
/// KeyboardShortcuts' own recorder is not used here: it keeps its choice in this process's
/// `UserDefaults.standard`, but only the menu bar app's counts. See docs/testing.md.
@MainActor
final class ShortcutRecorder {
    enum Result: Equatable {
        /// Esc: leave the Shortcut as it was.
        case cancel
        /// Delete: unassign the Shortcut.
        case clear
        case accept(ShortcutCombo)
        /// A plain key: a Shortcut needs ⌘, ⌃ or ⌥ (or to be a function key).
        case needsModifier
    }

    private var monitor: Any?

    func start(_ handler: @escaping @MainActor (Result) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let result = Self.interpret(keyCode: Int(event.keyCode), flags: event.modifierFlags)
            MainActor.assumeIsolated { handler(result) }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// What a key press means to a recorder.
    static func interpret(keyCode: Int, flags: NSEvent.ModifierFlags) -> Result {
        let modifiers = flags.intersection([.control, .option, .shift, .command])
        if modifiers.isEmpty {
            if keyCode == kVK_Escape { return .cancel }
            if keyCode == kVK_Delete || keyCode == kVK_ForwardDelete { return .clear }
        }
        let strong = !modifiers.intersection([.control, .option, .command]).isEmpty
        guard strong || ShortcutCombo.isFunctionKey(keyCode) else { return .needsModifier }
        return .accept(ShortcutCombo(keyCode: keyCode, modifiers: modifiers))
    }
}
