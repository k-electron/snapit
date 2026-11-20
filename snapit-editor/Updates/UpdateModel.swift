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

        var name: String {
            switch self {
            case .checking: "checking"
            case .answered(.newer): "newer"
            case .answered(.upToDate): "up-to-date"
            case .answered(.unreachable): "unreachable"
            }
        }
    }

    struct ButtonSpec {
        let id: String
        let title: String
        let tooltip: String
    }

    private(set) var state = State.checking

    /// Called when the user chooses Download or Close.
    var onClose: () -> Void = {}

    /// Starts a check: the window says it is checking, the menu bar app makes the one request and
    /// the answer replaces the line. A check already running is left alone: one click, one request.
    func check() {
        guard checkTask == nil else { return }
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

    // MARK: Words

    let title = "Check for Updates"

    /// The one line, or the headline of a newer release.
    var headline: String {
        switch state {
        case .checking: "Checking for updates…"
        case .answered(.newer(_, let version, _, _)): "snapit \(version) is available"
        case .answered(.upToDate(let installed)): "snapit \(installed) is up to date."
        case .answered(.unreachable(let reason)):
            switch reason {
            case .offline: "Couldn't reach GitHub. Check your connection and try again."
            case .timeout: "GitHub didn't answer in time. Try again in a moment."
            case .rateLimit: "GitHub is limiting requests right now. Try again in a little while."
            case .noRelease: "GitHub has no release of snapit to compare with."
            case .badResponse: "Couldn't read GitHub's answer. Try again later."
            case .ownVersion: "Couldn't read the version of this snapit."
            case .noAnswer: "snapit did not answer. Quit snapit and open it again."
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

    /// Only a newer release carries it: after updating, macOS blocks the new snapit again and its
    /// Screen Recording switch is off.
    var reminder: String? {
        guard case .answered(.newer) = state else { return nil }
        return "After updating, you need Open Anyway and Screen Recording again: open the new snapit, click Open Anyway in System Settings › Privacy & Security, then turn Screen Recording back on for snapit."
    }

    var downloadURL: URL? {
        guard case .answered(.newer(_, _, let url, _)) = state else { return nil }
        return URL(string: url)
    }

    let downloadButton = ButtonSpec(
        id: "download", title: "Download", tooltip: "Open this release's page on GitHub in your browser")
    let closeButton = ButtonSpec(id: "close", title: "Close", tooltip: "Close this window")

    var buttons: [ButtonSpec] {
        switch state {
        case .answered(.newer): [closeButton, downloadButton]
        default: [closeButton]
        }
    }

    /// Opens the release page in the browser and closes the window.
    func download() {
        guard let url = downloadURL else { return }
        BrowserLinks.open(url)
        onClose()
    }

    func close() { onClose() }
}
