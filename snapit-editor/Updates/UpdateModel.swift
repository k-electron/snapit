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
        /// An Update is running to the newer release this answer announced.
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
        didSet { blocks = ReleaseNotesBlocks.parse(notes ?? "") }
    }

    /// The release notes, parsed once when the answer arrives.
    private(set) var blocks: [NotesBlock] = []

    /// Called when the user chooses Release Page or Close.
    var onClose: () -> Void = {}

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

    // MARK: Words

    let title = "Check for Updates"

    /// The one line, or the headline of a newer release.
    var headline: String {
        switch state {
        case .checking: "Checking for updates…"
        case .answered(.newer(_, let version, _, _)): "snapit \(version) is available."
        case .installing(.newer(_, let version, _, _)): "Installing snapit \(version)…"
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

    /// Under the headline of a newer release.
    var detail: String? {
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

    var buttons: [HelperButton] {
        switch state {
        case .answered(.newer): [closeButton, releasePageButton, updateButton]
        default: [closeButton]
        }
    }

    /// Starts the Update: the menu bar app downloads the release, checks it, swaps it in and
    /// relaunches snapit. The window shows it is installing meanwhile. A successful Update quits
    /// this helper, so the request never comes back; one that comes back says the Update stopped,
    /// and the window offers the newer release again.
    func update() {
        guard case .answered(let answer) = state, case .newer(_, let version, _, _) = answer, installTask == nil else {
            return
        }
        state = .installing(answer)
        installTask = Task {
            let reply = try? await CommandSocketClient.send(
                .installUpdate, arguments: [version], to: AppIdentity.appSocketPath, timeoutSeconds: 1200)
            if reply != "ok" { state = .answered(answer) }
            installTask = nil
        }
    }

    private var installTask: Task<Void, Never>?

    /// Opens the release page in the browser and closes the window.
    func openReleasePage() {
        guard let url = releasePageURL else { return }
        BrowserLinks.open(url)
        onClose()
    }

    func close() { onClose() }
}
