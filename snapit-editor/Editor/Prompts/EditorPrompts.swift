import AppKit

/// What a prompt is about.
enum EditorPromptKind: Equatable {
    /// Closing an Editor whose Capture is not the Last Capture and has unexported edits.
    case close
    /// Quitting while Editors like that exist; `count` of them.
    case quit(count: Int)

    var name: String {
        switch self {
        case .close: "close"
        case .quit: "quit"
        }
    }

    var title: String {
        switch self {
        case .close: "Discard this Capture?"
        case .quit: "Quit snapit?"
        }
    }

    var message: String {
        switch self {
        case .close:
            "Its Annotations haven't been exported (copied, saved or dragged out), and this Capture can't be reopened once its Editor closes."
        case .quit(let count):
            count == 1
                ? "This Capture has Annotations you haven't exported. Quitting discards it."
                : "\(count) Captures have Annotations you haven't exported. Quitting discards them."
        }
    }

    var discardTitle: String {
        switch self {
        case .close: "Discard"
        case .quit: "Discard and Quit"
        }
    }

    var discardTooltip: String {
        switch self {
        case .close: "Discard this Capture and close its Editor"
        case .quit: "Discard the Captures you haven't exported and quit snapit"
        }
    }

    var cancelTooltip: String {
        switch self {
        case .close: "Keep this Editor open"
        case .quit: "Keep snapit open"
        }
    }
}

/// The one question an Editor can be waiting on: a macOS sheet on the Editor's window, answered
/// with Discard or Cancel. Esc is Cancel: nothing is lost by pressing it. The sheet never blocks the main thread: the answer arrives when a button is
/// pressed, so commands keep being served while it shows (a scripted run answers it through
/// `answer`).
@MainActor
final class EditorPrompts {
    static let shared = EditorPrompts()

    struct Shown {
        let kind: EditorPromptKind
        let session: EditorSession
        let alert: NSAlert
    }

    /// The prompt on screen, if any. There is at most one.
    private(set) var current: Shown?

    /// Asks `kind` on `session`'s Editor. True when the user chose Discard. False for Cancel, and
    /// when another prompt is already showing (that one is brought forward instead).
    func ask(_ kind: EditorPromptKind, in session: EditorSession) async -> Bool {
        if let current {
            current.session.bringForward()
            return false
        }
        guard let window = session.window else { return false }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = kind.title
        alert.informativeText = kind.message
        // AppKit gives Esc to the button titled Cancel.
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.toolTip = kind.cancelTooltip
        let discard = alert.addButton(withTitle: kind.discardTitle)
        discard.toolTip = kind.discardTooltip
        discard.hasDestructiveAction = true
        // Discard has a key of its own: ⌘D (Esc is Cancel's).
        discard.keyEquivalent = "d"
        discard.keyEquivalentModifierMask = .command
        current = Shown(kind: kind, session: session, alert: alert)
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { [weak self] response in
                self?.current = nil
                continuation.resume(returning: response == .alertSecondButtonReturn)
            }
        }
    }

    /// The Editor closed under its prompt (Copy closed it, say): the question is moot.
    func dismiss(for session: EditorSession) {
        guard let current, current.session === session, let window = session.window else { return }
        window.endSheet(current.alert.window, returnCode: .alertFirstButtonReturn)
    }

    /// Presses a button of the prompt on screen, as a click does; false when none is showing.
    @discardableResult
    func answer(discard: Bool) -> Bool {
        guard let current else { return false }
        current.alert.buttons[discard ? 1 : 0].performClick(nil)
        return true
    }
}
