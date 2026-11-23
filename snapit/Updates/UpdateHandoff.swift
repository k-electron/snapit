import Foundation

/// What the snapit that has just swapped itself for a newer one tells the copy it relaunches, on
/// that copy's command line. Only an Update's relaunch carries it; a copy started any other way
/// has none, so a normal launch and a normal quit behave as they always do (the Last Capture is
/// removed at quit and at launch).
///
/// - The Last Capture: the old copy leaves the Capture's files when it quits, and the new copy
///   takes that Capture over, so Reopen Last Capture brings it back with its Annotations.
/// - The leftovers: the staging folder of the Update holds the old copy of snapit. The new copy
///   deletes it (never to the Trash) once the old one has quit, if it is that Update's folder.
nonisolated struct UpdateHandoff: Equatable, Sendable {
    let oldProcessID: Int32
    let stagingFolder: URL
    /// The number of the Capture the old copy had as its Last Capture, if it had one.
    let lastCapture: Int?

    private static let processArgument = "--updated-from-pid="
    private static let stagingArgument = "--update-staging="
    private static let captureArgument = "--last-capture="

    var arguments: [String] {
        var arguments = [Self.processArgument + String(oldProcessID), Self.stagingArgument + stagingFolder.path]
        if let lastCapture { arguments.append(Self.captureArgument + String(lastCapture)) }
        return arguments
    }

    init(oldProcessID: Int32, stagingFolder: URL, lastCapture: Int?) {
        self.oldProcessID = oldProcessID
        self.stagingFolder = stagingFolder
        self.lastCapture = lastCapture
    }

    /// The handoff on a command line; nil for a launch that no Update made.
    init?(arguments: [String]) {
        func value(of prefix: String) -> String? {
            arguments.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        }
        guard let process = value(of: Self.processArgument).flatMap(Int32.init),
            let staging = value(of: Self.stagingArgument), !staging.isEmpty
        else { return nil }
        self.init(
            oldProcessID: process, stagingFolder: URL(fileURLWithPath: staging, isDirectory: true),
            lastCapture: value(of: Self.captureArgument).flatMap(Int.init))
    }

    /// Deletes the Update's staging folder, and the old copy of snapit in it, once the old copy has
    /// quit, and with it the staging folders of Updates that never finished. Never to the Trash. The
    /// folder named on the command line goes only if it is the one the old copy made for its Update
    /// (`UpdateStaging`). Runs off the main actor and returns at once.
    func removeLeftovers() {
        let process = oldProcessID
        let folder = stagingFolder
        Task.detached(priority: .utility) {
            let deadline = Date().addingTimeInterval(20)
            while kill(process, 0) == 0, Date() < deadline { try? await Task.sleep(for: .milliseconds(200)) }
            // An old copy that is still running needs its folder; a later Update sweeps it.
            guard kill(process, 0) != 0 else { return }
            UpdateStaging.remove(folder, madeBy: process)
            UpdateStaging.sweepAbandoned(in: folder.deletingLastPathComponent(), keeping: nil)
        }
    }
}
