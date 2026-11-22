import Foundation
import Observation

/// What the update window says and does. The view, the window and the test commands all read this
/// one model, so a line of text or a tooltip is written once.
@MainActor
@Observable
final class UpdateModel {
    enum State: Equatable {
        case checking
        case answered(UpdateAnswer)
        /// An Update is running to the newer release this answer announced; `progress` says how far.
        case installing(UpdateAnswer)

        var name: String {
            switch self {
            case .checking: "checking"
            case .answered(.newer): "newer"
            case .answered(.upToDate): "up-to-date"
            case .answered(.unreachable): "unreachable"
            case .installing: "installing"
            }
        }
    }

    private(set) var state = State.checking {
        didSet {
            blocks = ReleaseNotesBlocks.parse(notes ?? "")
            onChange()
        }
    }

    /// How far the Update has got, while one runs (the menu bar app's own account of it).
    private(set) var progress = UpdateProgress.downloading(received: 0, total: nil) {
        didSet { onChange() }
    }

    /// The release notes, parsed once when the answer arrives.
    private(set) var blocks: [NotesBlock] = []

    /// Called when the user chooses Release Page or Close, and when a cancelled Update has stopped.
    var onClose: () -> Void = {}

    /// Called when what the window may do changes (the window's close button follows `canClose`).
    var onChange: () -> Void = {}

    /// Starts a check: the window says it is checking, the menu bar app makes the one request and
    /// the answer replaces the line. A check already running is left alone: one click, one request.
    /// An Update that is running is left alone too.
    func check() {
        guard checkTask == nil, !isInstalling else { return }
        state = .checking
        checkTask = Task {
            let reply = try? await CommandSocketClient.send(
                .checkForUpdates, to: AppIdentity.appSocketPath, timeoutSeconds: 30)
            state = .answered(reply.flatMap(UpdateAnswer.init(wire:)) ?? .unreachable(.noAnswer))
            checkTask = nil
        }
    }

    private var checkTask: Task<Void, Never>?

    var isChecking: Bool { state == .checking }

    var isInstalling: Bool {
        if case .installing = state { return true }
        return false
    }

    /// What the scripted run reads as the window's state: `downloading` while the release comes in,
    /// `installing` from the moment it is being checked.
    var stateName: String {
        guard isInstalling else { return state.name }
        if case .downloading = progress { return "downloading" }
        return state.name
    }

    /// Cancel, and the window's close, still end the Update: it has not begun to swap in the new copy.
    var canCancel: Bool { isInstalling && progress.canCancel }

    /// The window may close now: it asks nothing of a running Update until the swap begins.
    var canClose: Bool { !isInstalling || progress.canCancel }

    /// How much of the disk image has arrived, 0 to 1; nil when it is not known (the bar then only moves).
    var progressFraction: Double? {
        guard isInstalling, let percent = progress.percent else { return nil }
        return Double(percent) / 100
    }

    // MARK: Words

    let title = "Check for Updates"

    /// The one line, or the headline of a newer release.
    var headline: String {
        switch state {
        case .checking: "Checking for updates…"
        case .answered(.newer(_, let version, _, _)): "snapit \(version) is available."
        case .installing(.newer(_, let version, _, _)):
            if case .downloading = progress { "Downloading snapit \(version)…" } else { "Installing snapit \(version)…" }
        case .installing: "Installing…"
        case .answered(.upToDate(let installed)): "snapit \(installed) is up to date."
        case .answered(.unreachable(let reason)):
            switch reason {
            case .offline: "Couldn't reach GitHub. Check your connection and try again."
            case .timeout: "GitHub didn't answer in time. Try again in a moment."
            case .rateLimit: "GitHub is limiting requests right now. Try again in a little while."
            case .noRelease: "GitHub has no release of snapit to compare with."
            case .badResponse: "Couldn't read GitHub's answer. Try again later."
            case .ownVersion: "Couldn't read the version of this snapit."
            case .noAnswer: "snapit didn't answer. Quit snapit and open it again."
            }
        }
    }

    /// Under the headline: what is installed, for a newer release; how much has arrived, while it downloads.
    var detail: String? {
        if case .downloading(let received, let total) = progress, isInstalling {
            guard let total, total > 0 else { return nil }
            let format = ByteCountFormatter()
            format.countStyle = .file
            return "\(format.string(fromByteCount: received)) of \(format.string(fromByteCount: total))"
        }
        guard case .answered(.newer(let installed, _, _, _)) = state else { return nil }
        return "You have snapit \(installed)."
    }

    var notes: String? {
        guard case .answered(.newer(_, _, _, let notes)) = state else { return nil }
        return notes
    }

    /// Only a newer release carries it: after an Update, macOS has not been given Screen Recording
    /// for the new snapit yet.
    var reminder: String? {
        guard case .answered(.newer) = state else { return nil }
        return "After updating, turn Screen Recording back on for snapit: the new snapit asks for it."
    }

    /// The release page of the newer release the window announces.
    var releasePageURL: URL? {
        guard case .answered(.newer(_, _, let url, _)) = state else { return nil }
        return URL(string: url)
    }

    let updateButton = HelperButton(
        id: "update", title: "Update and Relaunch",
        tooltip: "Install this version of snapit and relaunch it")
    let releasePageButton = HelperButton(
        id: "release-page", title: "Release Page", tooltip: "Open this release's page on GitHub in your browser")
    let closeButton = HelperButton(id: "close", title: "Close", tooltip: "Close this window")
    let cancelButton = HelperButton(
        id: "cancel", title: "Cancel", tooltip: "Stop the Update and leave snapit as it is")

    var buttons: [HelperButton] {
        switch state {
        case .answered(.newer): [closeButton, releasePageButton, updateButton]
        case .installing: [cancelButton]
        default: [closeButton]
        }
    }

    // MARK: Update

    /// Starts the Update. Editors that are not the Last Capture's and hold edits that were never
    /// Exported are asked about first, with Quit's question: Cancel ends the Update before anything
    /// is downloaded. Then the menu bar app downloads the release, checks it, swaps it in and
    /// relaunches snapit; the window shows how far it has got, and Cancel (or closing the window)
    /// ends the Update until the swap begins. A successful Update quits this helper, so the request
    /// never comes back; one that comes back says the Update stopped, and the window offers the
    /// newer release again.
    func update() {
        guard case .answered(let answer) = state, case .newer(_, let version, _, _) = answer, installTask == nil else {
            return
        }
        installTask = Task {
            // A window closed while the question was up leaves nothing to show an Update in.
            guard await QuitPreparation.confirm(), !windowClosed else {
                installTask = nil
                return
            }
            progress = .downloading(received: 0, total: nil)
            state = .installing(answer)
            let polling = Task { await pollProgress() }
            let reply = try? await CommandSocketClient.send(
                .installUpdate, arguments: [version], to: AppIdentity.appSocketPath, timeoutSeconds: 1200)
            polling.cancel()
            if reply != "ok" { state = .answered(answer) }
            installTask = nil
        }
    }

    private var installTask: Task<Void, Never>?
    private var cancelTask: Task<Void, Never>?
    private var windowClosed = false

    /// The menu bar app owns the Update, so the window asks it how far it has got.
    private func pollProgress() async {
        while !Task.isCancelled {
            let reply = try? await CommandSocketClient.send(
                .updateStatus, to: AppIdentity.appSocketPath, timeoutSeconds: 5)
            if let latest = reply.flatMap(UpdateProgress.init(wire:)), latest != .idle, isInstalling, !Task.isCancelled {
                progress = latest
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Ends the running Update with nothing changed; with `thenClose`, closes the window once the menu
    /// bar app says the Update has stopped and its files are gone (the helper may quit when its last
    /// window closes, so it must not go before the menu bar app has heard).
    func cancel(thenClose: Bool = false) {
        guard canCancel, cancelTask == nil else { return }
        cancelTask = Task {
            let reply = try? await CommandSocketClient.send(
                .cancelUpdate, to: AppIdentity.appSocketPath, timeoutSeconds: 30)
            cancelTask = nil
            if thenClose, reply == "ok" || reply?.hasPrefix("error no Update") == true { onClose() }
        }
    }

    /// What the window's close button, ⌘W and the Close button ask: whether the window closes now.
    /// A running Update is cancelled first, and the window closes when it has stopped.
    func requestClose() -> Bool {
        guard isInstalling else { return true }
        cancel(thenClose: true)
        return false
    }

    /// The window is gone.
    func windowDidClose() { windowClosed = true }

    /// Opens the release page in the browser and closes the window.
    func openReleasePage() {
        guard let url = releasePageURL else { return }
        BrowserLinks.open(url)
        onClose()
    }

    func close() {
        if requestClose() { onClose() }
    }
}
