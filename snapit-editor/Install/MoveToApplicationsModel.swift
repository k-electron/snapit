import Foundation
import Observation

/// What the "Move snapit to Applications" screen says and does. The view, the window and the
/// test commands all read this one model, so a tooltip or a title is written once.
@MainActor
@Observable
final class MoveToApplicationsModel {
    enum Reason: String {
        /// snapit runs from a mounted disk image.
        case diskImage = "disk-image"
        /// macOS runs snapit from a temporary (translocated) path.
        case temporary
    }

    enum State: Equatable {
        case ready
        case moving
        case failed(String)

        var name: String {
            switch self {
            case .ready: "ready"
            case .moving: "moving"
            case .failed: "failed"
            }
        }
    }

    struct ButtonSpec {
        let id: String
        let title: String
        let tooltip: String
    }

    let reason: Reason
    /// True when a copy of snapit already sits in Applications and the move replaces it.
    let replacesExisting: Bool
    private(set) var state = State.ready

    /// Called when the user chooses Not Now.
    var onLater: () -> Void = {}

    init(reason: Reason, replacesExisting: Bool) {
        self.reason = reason
        self.replacesExisting = replacesExisting
    }

    let title = "Move snapit to Applications"

    var message: String {
        switch reason {
        case .diskImage:
            "snapit is running from a disk image. Move it to Applications so launch at login and updates keep working. snapit relaunches from there and ejects the disk image."
        case .temporary:
            "macOS is running snapit from a temporary location. Move it to Applications so launch at login and updates keep working. snapit relaunches from there."
        }
    }

    var replaceNote: String? {
        replacesExisting ? "The snapit already in Applications is replaced." : nil
    }

    let moveButton = ButtonSpec(
        id: "move", title: "Move to Applications", tooltip: "Copy snapit to Applications and relaunch it from there")
    let laterButton = ButtonSpec(id: "later", title: "Not Now", tooltip: "Keep running snapit from here")

    var buttons: [ButtonSpec] { [moveButton, laterButton] }

    /// Asks the menu bar app to move. Replies `ok` when it is relaunching (it quits, and the
    /// helper with it, a moment later) or the reason it could not.
    func move() async -> String {
        guard state != .moving else { return "error already moving" }
        state = .moving
        do {
            let reply = try await CommandSocketClient.send(
                .moveToApplications, to: AppIdentity.appSocketPath, timeoutSeconds: 120)
            if reply == "ok" { return reply }
            state = .failed(reply.hasPrefix("error ") ? String(reply.dropFirst(6)) : reply)
            return reply
        } catch {
            state = .failed("snapit did not answer. Quit snapit and open it again.")
            return "error \(error)"
        }
    }

    func later() {
        guard state != .moving else { return }
        onLater()
    }
}
