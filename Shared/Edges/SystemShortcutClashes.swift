import AppKit
import Carbon.HIToolbox

/// Which key combinations macOS already uses for its own shortcuts (the symbolic hot keys:
/// Screenshots, Spotlight, Mission Control and so on). Settings flags a Shortcut that clashes.
/// Always go through `SystemShortcuts.current`.
protocol SystemShortcutClashes {
    func isTaken(_ combo: ShortcutCombo) -> Bool
}

enum SystemShortcuts {
    static let current: any SystemShortcutClashes = TestMode.isActive ? FixtureSystemShortcuts() : SystemShortcutTable()
}

/// macOS's enabled symbolic hot keys, read from the system when asked.
struct SystemShortcutTable: SystemShortcutClashes {
    func isTaken(_ combo: ShortcutCombo) -> Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr, let list = unmanaged?.takeRetainedValue() as? [[String: Any]]
        else { return false }
        let wanted = Self.carbonModifiers(combo.modifiers)
        return list.contains { entry in
            guard (entry["kHISymbolicHotKeyEnabled"] as? NSNumber)?.boolValue == true,
                let code = (entry["kHISymbolicHotKeyCode"] as? NSNumber)?.intValue, code == combo.keyCode,
                let modifiers = (entry["kHISymbolicHotKeyModifiers"] as? NSNumber)?.intValue
            else { return false }
            return modifiers & Self.relevant == wanted
        }
    }

    private static let relevant = cmdKey | shiftKey | optionKey | controlKey

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var value = 0
        if flags.contains(.command) { value |= cmdKey }
        if flags.contains(.shift) { value |= shiftKey }
        if flags.contains(.option) { value |= optionKey }
        if flags.contains(.control) { value |= controlKey }
        return value
    }
}

/// Test mode's table: ⌘⇧3, ⌘⇧4 and ⌘⇧5, macOS's screenshot keys, so a run never depends on what
/// the machine's own settings say. A run can add combinations (`taken`), as a user's own macOS
/// shortcuts would; they are kept in the run's defaults, so both processes see them.
struct FixtureSystemShortcuts: SystemShortcutClashes {
    static let takenKey = "test.systemShortcutsTaken"

    /// The combinations a run added, one per line in the wire form (`ShortcutCombo.wire`).
    static var taken: [String] {
        get { (AppDefaults.store.string(forKey: takenKey) ?? "").split(separator: "\n").map(String.init) }
        set { AppDefaults.store.set(newValue.joined(separator: "\n"), forKey: takenKey) }
    }

    func isTaken(_ combo: ShortcutCombo) -> Bool {
        if [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5].contains(combo.keyCode) && combo.modifiers == [.command, .shift] { return true }
        return Self.taken.contains(ShortcutCombo.wire(combo))
    }
}
