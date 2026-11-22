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
        /// The Update stopped, for this cause; the answer is the newer release it was updating to.
        case failed(UpdateAnswer, UpdateFailure)

        var name: String {
            switch self {
            case .checking: "checking"
            case .answered(.newer): "newer"
            case .answered(.upToDate): "up-to-date"
            case .answered(.unreachable): "unreachable"
            case .installing: "installing"
            case .failed: "failed"
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
            let answer = reply.flatMap(UpdateAnswer.init(wire:)) ?? .unreachable(.noAnswer)
            // Asked before the answer shows, so the window never offers Update and Relaunch where
            // it cannot update.
            if case .newer = answer {
                let place = try? await CommandSocketClient.send(
                    .updateCanInstall, to: AppIdentity.appSocketPath, timeoutSeconds: 10)
                canInstallHere = place != "no"
            }
            state = .answered(answer)
            checkTask = nil
        }
    }

    private var checkTask: Task<Void, Never>?

    var isChecking: Bool { state == .checking }

    /// False when this copy runs from a disk image or from a folder it cannot write to: it cannot
    /// update itself there.
    private(set) var canInstallHere = true

    /// What the scripted run reads as the window's state: `cannot-install` for a newer release this
    /// copy cannot install where it runs.
    var stateName: String {
        if case .answered(.newer) = state, !canInstallHere { return "cannot-install" }
        return state.name
    }

    /// The newer release the window announces, in the states that announce one.
    private var announced: (installed: String, version: String, url: String, notes: String)? {
        switch state {
        case .answered(.newer(let installed, let version, let url, let notes)),
            .failed(.newer(let installed, let version, let url, let notes), _):
            return (installed, version, url, notes)
        default: return nil
        }
    }

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
        case .answered(.newer(_, let version, _, _)), .failed(.newer(_, let version, _, _), _):
            "snapit \(version) is available."
        case .installing(.newer(_, let version, _, _)): "Installing snapit \(version)…"
        case .installing: "Installing…"
        case .failed: "The Update couldn't finish."
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
        guard let announced else { return nil }
        return "You have snapit \(announced.installed)."
    }

    /// The line under the headline: why the Update stopped, or why it is not offered here.
    var notice: String? {
        if case .failed(_, let failure) = state { return failure.line }
        if case .answered(.newer) = state, !canInstallHere { return UpdateFailure.moveLine }
        return nil
    }

    var notes: String? { announced?.notes }

    /// Only a newer release carries it: after an Update, macOS has not been given Screen Recording
    /// for the new snapit yet.
    var reminder: String? {
        guard case .answered(.newer) = state, canInstallHere else { return nil }
        return "After updating, turn Screen Recording back on for snapit: the new snapit asks for it."
    }

    /// The release page of the newer release the window announces.
    var releasePageURL: URL? {
        announced.flatMap { URL(string: $0.url) }
    }

    let updateButton = HelperButton(
        id: "update", title: "Update and Relaunch",
        tooltip: "Install this version of snapit and relaunch it")
    let releasePageButton = HelperButton(
        id: "release-page", title: "Release Page", tooltip: "Open this release's page on GitHub in your browser")
    let closeButton = HelperButton(id: "close", title: "Close", tooltip: "Close this window")

    var buttons: [HelperButton] {
        switch state {
        case .answered(.newer): canInstallHere ? [closeButton, releasePageButton, updateButton] : [closeButton, releasePageButton]
        // The Update can be tried again.
        case .failed: [closeButton, releasePageButton, updateButton]
        default: [closeButton]
        }
    }

    /// Starts the Update: the menu bar app downloads the release, checks it, swaps it in and
    /// relaunches snapit. The window shows it is installing meanwhile. A successful Update quits
    /// this helper, so the request never comes back; one that comes back says the Update stopped,
    /// and the window offers the newer release again.
    func update() {
        let answer: UpdateAnswer
        switch state {
        case .answered(let newer), .failed(let newer, _): answer = newer
        default: return
        }
        guard case .newer(_, let version, _, _) = answer, canInstallHere, installTask == nil else { return }
        state = .installing(answer)
        installTask = Task {
            let reply = try? await CommandSocketClient.send(
                .installUpdate, arguments: [version], to: AppIdentity.appSocketPath, timeoutSeconds: 1200)
            if reply != "ok" { state = .failed(answer, Self.failure(in: reply)) }
            installTask = nil
        }
    }

    private var installTask: Task<Void, Never>?

    /// The cause a reply of `install-update` names: `error <cause> <description>`. No reply at all
    /// is the menu bar app not answering.
    private static func failure(in reply: String?) -> UpdateFailure {
        guard let reply else { return .noAnswer }
        let words = reply.split(separator: " ", maxSplits: 2)
        guard words.count >= 2, words[0] == "error" else { return .other }
        return UpdateFailure(cause: String(words[1]))
    }

    /// Opens the release page in the browser and closes the window.
    func openReleasePage() {
        guard let url = releasePageURL else { return }
        BrowserLinks.open(url)
        onClose()
    }

    func close() { onClose() }
}
