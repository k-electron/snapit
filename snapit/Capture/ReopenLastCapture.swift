import Foundation

/// "Reopen Last Capture": asks the Editor helper to bring the Last Capture back, with its
/// Annotations, crop and Undo history. The pixels come from the Capture file as they are (mapped,
/// not decoded); the helper reads the state file beside them.
///
/// An Editor already open for the Last Capture just comes forward. A store that cannot be read
/// makes the helper tell the user ("That Capture couldn't be reopened."), and the Last Capture is
/// dropped, so the menu item greys out instead of failing again.
@MainActor
enum ReopenLastCapture {
    enum Outcome: Equatable {
        /// The Last Capture is showing in the Editor.
        case opened(number: Int)
        /// There is no Last Capture.
        case none
        /// A Reopen is already under way.
        case busy
        /// The stored Capture is damaged; the helper told the user and the Last Capture is gone.
        case couldNotReopen
        case failed(String)
    }

    private static var running = false

    @discardableResult
    static func run() async -> Outcome {
        guard let number = LastCapture.shared.number else { return .none }
        guard !running else { return .busy }
        running = true
        defer { running = false }
        do {
            try await EditorHelperLauncher.open(capture: number, command: .reopenCapture)
            return .opened(number: number)
        } catch EditorHelperError.refused(let reply) where reply.contains("could-not-reopen") {
            CaptureHandoff.delete(number: number)
            return .couldNotReopen
        } catch {
            NSLog("snapit: Reopen Last Capture failed: \(error)")
            return .failed("\(error)")
        }
    }
}
