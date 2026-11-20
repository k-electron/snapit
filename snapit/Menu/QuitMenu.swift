import AppKit
import SwiftUI

/// A separator, then Quit snapit, last in the menu.
struct QuitMenu: MenuSection {
    var entries: [MenuEntry] {
        [
            .separator(id: "quit.separator"),
            .action(id: "quit", "Quit snapit", shortcut: KeyboardShortcut("q")) {
                // An Editor with unexported edits is brought forward and the user asked first;
                // Cancel keeps snapit running.
                guard await EditorHelperQuitCheck.allowsQuit() else { return }
                NSApplication.shared.terminate(nil)
            },
        ]
    }
}

/// The pre-quit command: before the menu bar app quits, the Editor helper (when one is running)
/// is asked whether quitting may go ahead. It asks the user about Editors holding unexported
/// edits, bringing the first one forward, and answers `cancel` when the user keeps snapit open.
enum EditorHelperQuitCheck {
    /// How long the helper may take to answer: the user decides, so no time limit that matters.
    private static let answerTimeoutSeconds = 3600

    /// True when snapit may quit: no helper is running, nothing is at risk, or the user chose to
    /// discard. Only `ok` is consent. Anything else (`cancel`, or no answer within the time limit)
    /// keeps snapit running while the helper is still there to protect an Editor.
    static func allowsQuit() async -> Bool {
        let path = AppIdentity.editorSocketPath
        guard await CommandSocketClient.isListening(at: path) else { return true }
        let reply = try? await CommandSocketClient.send(.confirmQuit, to: path, timeoutSeconds: answerTimeoutSeconds)
        if reply == "ok" { return true }
        if reply == "cancel" { return false }
        // No answer: a helper that is gone has nothing left to lose.
        return !(await CommandSocketClient.isListening(at: path))
    }
}
