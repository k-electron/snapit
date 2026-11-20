import Foundation

nonisolated extension SocketCommand {
    /// The menu bar app asks the Editor helper, before it quits, whether quitting may go ahead:
    /// the helper asks the user when an Editor holds unexported edits and replies `ok` (quit) or
    /// `cancel` (the user chose to keep snapit open). It is not a second `quit`: nothing quits.
    static let confirmQuit = SocketCommand("confirm-quit")
}

/// What a process does around quitting. `quit` (the built-in command) and the Editor helper's own
/// "Quit snapit" menu item both go through here.
///
/// - `confirmations` come first and may cancel the quit (the Quit prompt for Editors with
///   unexported edits). Only a quit the user starts asks: the `quit` command, sent after the user
///   has been asked (or by a scripted run's clean-up), never does.
/// - `steps` then run before the process quits: the built-in `quit` command awaits every step, then
///   replies and terminates.
///
/// A feature that needs something done first appends a step where it registers its commands; a
/// step is never a second handler for `quit` (a command has one handler; registering a second
/// would silently replace this one). The Last Capture's step stops its state writes and waits for
/// the queue to drain, so the menu bar app can remove the files knowing nothing will recreate
/// them.
@MainActor
enum QuitPreparation {
    static var steps: [@MainActor () async -> Void] = []
    static var confirmations: [@MainActor () async -> Bool] = []
    /// True once the steps have run: the quit is decided and nothing may be asked any more.
    private(set) static var hasRun = false

    /// False when any confirmation says the user wants to keep the app open.
    static func confirm() async -> Bool {
        for confirmation in confirmations {
            let agreed = await confirmation()
            if !agreed { return false }
        }
        return true
    }

    static func run() async {
        hasRun = true
        for step in steps { await step() }
    }
}
