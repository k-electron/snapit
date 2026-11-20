import Foundation

/// What a process does before it quits when the other process (or its own "Quit snapit") asks it
/// to: the built-in `quit` command awaits every step, then replies and terminates, and the Editor
/// helper's own "Quit snapit" menu item runs the same steps.
///
/// A feature that needs something done first appends a step where it registers its commands; a
/// step is never a second handler for `quit` (a command has one handler; registering a second
/// would silently replace this one). The Last Capture's step stops its state writes and waits for
/// the queue to drain, so the menu bar app can remove the files knowing nothing will recreate
/// them. The Quit prompt for unexported Editors is a separate command or step of its own.
@MainActor
enum QuitPreparation {
    static var steps: [@MainActor () async -> Void] = []

    static func run() async {
        for step in steps { await step() }
    }
}
