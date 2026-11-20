import Foundation

nonisolated extension SocketCommand {
    /// `warm-up <menu bar app pid>`: the menu bar app tells the Editor helper a Capture has
    /// started. The helper builds an Editor window ahead of its Capture, hidden, watches that
    /// process and quits with it while it has shown nothing, and replies `ok`. Replies `ok` again
    /// when one is already built.
    static let warmUp = SocketCommand("warm-up")
    /// `cancel-warm-up`: the Capture was cancelled. The helper throws the warm Editor away and,
    /// when it has never shown a window, stops answering and quits. A helper with an Editor open stays.
    static let cancelWarmUp = SocketCommand("cancel-warm-up")
}
