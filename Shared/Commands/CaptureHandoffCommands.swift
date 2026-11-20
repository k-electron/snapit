import Foundation

nonisolated extension SocketCommand {
    /// `open-capture <N>`: the menu bar app tells the Editor helper to open Capture N from its
    /// Capture file (`CaptureFiles`). Replies `ok` once the Editor window is showing.
    static let openCapture = SocketCommand("open-capture")
    /// `reopen-capture <N>`: the menu bar app tells the Editor helper to bring the Last Capture
    /// back: its pixels from the Capture file and its Annotations, crop and Undo history from the
    /// state file. Replies `ok` once the Editor is showing (an Editor already open for it just comes
    /// forward), or `error could-not-reopen` when the stored Capture is damaged, after the helper
    /// has told the user.
    static let reopenCapture = SocketCommand("reopen-capture")
    /// `delete-capture <N>`: the helper tells the menu bar app the user deleted Capture N, so it
    /// removes the Capture file. Replies `ok`.
    static let deleteCapture = SocketCommand("delete-capture")
}
