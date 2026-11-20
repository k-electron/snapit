import AppKit
import Carbon.HIToolbox

extension ShortcutCombo {
    /// How the combination reads in Settings: modifiers in the order macOS draws them, then the
    /// key, for example ⌃⌥⌘4.
    var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    private static let namedKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
        kVK_F20: "F20",
    ]

    /// Whether a key may be a Shortcut without a modifier (the function keys).
    static func isFunctionKey(_ keyCode: Int) -> Bool {
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
            kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        return functionKeys.contains(keyCode)
    }

    /// The key's name on the current keyboard layout, from the layout's own tables.
    private static func keyName(_ keyCode: Int) -> String {
        if let named = namedKeys[keyCode] { return named }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "Key \(keyCode)" }
        let layout = unsafeBitCast(data, to: CFData.self)
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = CFDataGetBytePtr(layout).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
            UCKeyTranslate(
                $0, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}
