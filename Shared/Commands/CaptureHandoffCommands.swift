import Foundation

nonisolated extension SocketCommand {
    /// `open-capture <N>`: the menu bar app tells the Editor helper to open Capture N from its
    /// Capture file (`CaptureFiles`). Replies `ok` once the Editor window is showing.
    static let openCapture = SocketCommand("open-capture")
    /// `delete-capture <N>`: the helper tells the menu bar app the user deleted Capture N, so it
    /// removes the Capture file. Replies `ok`.
    static let deleteCapture = SocketCommand("delete-capture")
}
