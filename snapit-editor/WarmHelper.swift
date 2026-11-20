import AppKit

/// The warm-up side of the helper's lifecycle: a helper that has shown nothing quits when its
/// Capture is cancelled, and when the menu bar app that started it goes away, so no helper
/// process is left at rest.
@MainActor
enum WarmHelper {
    private static var watchedPID: pid_t?
    private static var menuBarApp: DispatchSourceProcess?

    /// The menu bar app's process ID, from the launch arguments.
    static var launchPID: pid_t? {
        CommandLine.arguments
            .first { $0.hasPrefix(AppIdentity.menuBarPIDArgumentPrefix) }
            .flatMap { pid_t($0.dropFirst(AppIdentity.menuBarPIDArgumentPrefix.count)) }
    }

    /// Builds the Editor ahead of its Capture and starts watching the menu bar app that asked.
    static func warmUp(menuBarPID: pid_t?) {
        EditorSessions.shared.warmUp()
        if let menuBarPID { watch(menuBarPID) }
    }

    /// Quits when no window has ever shown and no Editor is open: stops answering at once (a
    /// Capture that arrives from here on starts a new helper), then terminates after the reply
    /// to the command that asked has gone out. A helper with an Editor open stays.
    static func quitIfNothingOpen() {
        guard !HelperLifecycle.hasShownWindow, EditorSessions.shared.sessions.isEmpty else { return }
        (NSApp.delegate as? HelperDelegate)?.stopServing()
        NSApplication.terminateAfterReply()
    }

    /// Calls `quitIfNothingOpen()` when the menu bar app exits (it was killed, crashed or quit),
    /// event driven: nothing runs until then. A menu bar app that is already gone counts too.
    private static func watch(_ pid: pid_t) {
        guard pid > 1, pid != watchedPID else { return }
        menuBarApp?.cancel()
        watchedPID = pid
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { quitIfNothingOpen() } }
        source.resume()
        menuBarApp = source
        if kill(pid, 0) == -1 && errno == ESRCH { quitIfNothingOpen() }
    }
}
