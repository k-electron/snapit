import AppKit

/// The close rule: "don't over-protect Captures the user never Exported". Closing asks once, and
/// only for an Editor that is not the Last Capture's (the Last Capture can be reopened) and has
/// edits that were never Exported. Delete Capture, Copy and Save never ask (`close()`).
extension EditorSession {
    /// Finishes the text still being typed, so it counts as an edit before the rule looks at the
    /// document. Called before every count of unexported edits (a close, a Quit).
    func commitPendingEdits() {
        commitTextEditing(refocus: false)
    }

    /// True when closing this Editor would lose edits the user never Exported and cannot reopen.
    var closeWouldLoseWork: Bool {
        !isLastCapture && document?.hasUnexportedEdits == true
    }

    /// Closes the Editor the way the user asks to (the close button, ⌘W, Esc): at once, or after
    /// asking once when `closeWouldLoseWork`.
    func requestClose() {
        guard !isClosing else { return }
        commitPendingEdits()
        guard closeWouldLoseWork else { return close() }
        Task {
            if await EditorPrompts.shared.ask(.close, in: self) { close() }
        }
    }
}

extension EditorSessions {
    /// The open Editors that Quit would lose edits of, oldest Capture first.
    func editorsAtRisk() -> [EditorSession] {
        sessions.values.forEach { $0.commitPendingEdits() }
        return captureNumbers.compactMap { sessions[$0] }.filter(\.closeWouldLoseWork)
    }

    /// Quit's question: brings the first Editor with unexported edits forward and asks once for all
    /// of them. True when nothing is at risk, or the user chose to discard.
    func confirmQuit() async -> Bool {
        let atRisk = editorsAtRisk()
        guard let first = atRisk.first else { return true }
        first.bringForward()
        return await EditorPrompts.shared.ask(.quit(count: atRisk.count), in: first)
    }
}
