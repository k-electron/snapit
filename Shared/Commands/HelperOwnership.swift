import Darwin
import Foundation

/// Whose an Editor helper is, from the process ID it reports (`helper-owner`).
///
/// A helper belongs to the menu bar app that started it. When that copy is gone (it crashed or was
/// killed) the helper stays, with the user's open Editors, and the next copy uses it and quits it with
/// itself. A helper whose copy is still running belongs to that copy: it is not touched by another one,
/// except by a copy that has taken over from it (a relaunch), which retires it.
nonisolated enum HelperOwnership {
    /// True when this copy may treat the helper as its own: `reply` (a `helper-owner` reply, nil when no
    /// helper answers) names this process, names no process, or names one that no longer runs.
    static func isOurs(_ reply: String?) -> Bool {
        guard let reply, let pid = Int32(reply) else { return true }
        if pid == getpid() { return true }
        return kill(pid, 0) == -1 && errno == ESRCH
    }
}
