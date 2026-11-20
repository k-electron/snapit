import Foundation

nonisolated extension SocketCommand {
    /// `warm-up`: the menu bar app tells the Editor helper a Capture has started. The helper
    /// builds an Editor window ahead of its Capture, hidden, and replies `ok`. Replies `ok` again
    /// when one is already built.
    static let warmUp = SocketCommand("warm-up")
    /// `cancel-warm-up`: the Capture was cancelled. The helper throws the warm Editor away and,
    /// when it has never shown a window, quits. A helper with an Editor open stays.
    static let cancelWarmUp = SocketCommand("cancel-warm-up")
}
