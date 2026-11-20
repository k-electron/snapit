import AppKit
import SwiftUI

/// Quit snapit, last in the menu.
struct QuitMenu: MenuSection {
    var entries: [MenuEntry] {
        [.action(id: "quit", "Quit snapit", shortcut: KeyboardShortcut("q")) {
            // An Editor with unexported edits is brought forward and the user asked first; Cancel
            // keeps snapit running.
            guard await EditorHelperQuitCheck.allowsQuit() else { return }
            NSApplication.shared.terminate(nil)
        }]
    }
}

/// The pre-quit command: before the menu bar app quits, the Editor helper (when one is running)
/// is asked whether quitting may go ahead. It asks the user about Editors holding unexported
/// edits, bringing the first one forward, and answers `cancel` when the user keeps snapit open.
enum EditorHelperQuitCheck {
    /// How long the helper may take to answer: the user decides, so no time limit that matters.
    private static let answerTimeoutSeconds = 3600

    /// True when snapit may quit: no helper is running, nothing is at risk, the user chose to
    /// discard, or the helper cannot be asked.
    static func allowsQuit() async -> Bool {
        let path = AppIdentity.editorSocketPath
        guard await CommandSocketClient.isListening(at: path) else { return true }
        let reply = try? await CommandSocketClient.send(.confirmQuit, to: path, timeoutSeconds: answerTimeoutSeconds)
        return reply != "cancel"
    }
}
