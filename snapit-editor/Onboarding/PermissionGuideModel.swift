import Foundation
import Observation

/// A button of Onboarding or of a Permission guide: its id, its words and its hover tooltip. The
/// windows draw from these and the scripted run reads them back, so the words are written once.
struct HelperButton {
    let id: String
    let title: String
    let tooltip: String
}

/// The Screen Recording Permission guide: what it says, which drawing it plays and what its buttons
/// do. Onboarding's second step and the guide's own window show the same model.
///
/// Screen Recording is the menu bar app's: it asks macOS and answers over the socket. The guide
/// looks at where the permission stands only when the window it is in becomes active (and when it
/// first appears), never on a timer: after macOS's prompt or System Settings, coming back to
/// snapit's window is the moment the answer can have changed.
///
/// The guide tells people to turn snapit on, never to toggle an existing switch: after an update
/// that switch looks on and does nothing, so snapit clears its own old entry first.
@MainActor
@Observable
final class PermissionGuideModel {
    /// Which drawing plays.
    enum Variant: String {
        /// macOS's own message, then System Settings.
        case prompt
        /// Only System Settings: macOS does not ask again after "Don't Allow".
        case systemSettings
    }

    let kind: PermissionGuideKind
    let animation = GuideAnimation()

    /// Where Screen Recording stood at the last look; nil before the first answer.
    private(set) var state: ScreenRecordingState?
    private(set) var variant = Variant.prompt
    /// True when snapit found its Screen Recording gone after it had been granted (an update).
    private(set) var isUpdate = false
    private(set) var resetFailure: String?
    private(set) var relaunchError: String?
    /// How many times the guide looked at the permission.
    private(set) var checks = 0

    /// The guide is on the page its window shows (Onboarding's second step, or its own window).
    var isShown = false { didSet { updateAnimation() } }
    /// The window is on screen: not hidden, minimised or fully covered.
    var isVisible = false { didSet { updateAnimation() } }

    @ObservationIgnored private var needsCheck = true
    @ObservationIgnored private var isChecking = false
    @ObservationIgnored private var hasAsked = false

    init(kind: PermissionGuideKind = .screenRecording) { self.kind = kind }

    var isGranted: Bool { state == .granted }

    // MARK: Looking at the permission

    /// The window became active (or the guide just appeared in an active window): look at where
    /// Screen Recording stands. The first look also asks macOS, once.
    func windowBecameActive() async {
        guard needsCheck, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        needsCheck = false
        checks += 1
        guard let reply = try? await CommandSocketClient.send(.screenRecordingState, to: AppIdentity.appSocketPath),
            let current = ScreenRecordingState(rawValue: reply)
        else {
            needsCheck = true
            return
        }
        if !hasAsked {
            hasAsked = true
            isUpdate = current == .grantedStale
            switch current {
            case .notDetermined, .grantedStale:
                await ask()
            case .denied:
                state = current
                variant = .systemSettings
            case .granted:
                state = current
            }
        } else {
            state = current
            if current == .denied { variant = .systemSettings }
        }
        updateAnimation()
    }

    /// The window lost focus (macOS's prompt, System Settings or another app took it): the next
    /// time it becomes active is a new look.
    func windowResigned() { needsCheck = true }

    /// Asks macOS afresh through the menu bar app. After an update it first clears snapit's own old
    /// entry.
    private func ask() async {
        guard
            let reply = try? await CommandSocketClient.send(
                .screenRecordingRequest, to: AppIdentity.appSocketPath, timeoutSeconds: 20)
        else { return }
        let lines = reply.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        state = lines.first.flatMap(ScreenRecordingState.init(rawValue:))
        resetFailure = lines.dropFirst().first { $0.hasPrefix("reset-failed ") }.map { String($0.dropFirst("reset-failed ".count)) }
    }

    // MARK: Buttons

    func openSystemSettings() { SystemSettingsLinks.open(.screenRecording) }

    /// Relaunches snapit (the menu bar app, which holds the permission). The helper goes with it.
    func relaunch() async {
        do {
            let reply = try await CommandSocketClient.send(.relaunchSnapit, to: AppIdentity.appSocketPath, timeoutSeconds: 15)
            relaunchError = reply == "ok" ? nil : reply.replacingOccurrences(of: "error ", with: "")
        } catch {
            relaunchError = "snapit did not answer. Quit snapit and open it again."
        }
    }

    func replay() { if animation.state == .stopped { animation.play() } }

    // MARK: Words

    let openSystemSettingsButton = HelperButton(
        id: "open-system-settings", title: "Open System Settings",
        tooltip: "Open System Settings at Privacy & Security › Screen Recording")
    let relaunchButton = HelperButton(
        id: "relaunch", title: "Relaunch snapit",
        tooltip: "Relaunch snapit, if you turned Screen Recording on and chose Later")
    let replayButton = HelperButton(id: "replay", title: "Replay", tooltip: "Play the animation again")

    var buttons: [HelperButton] {
        guard let state, state != .granted else { return [] }
        var list = [openSystemSettingsButton]
        if variant == .systemSettings || resetFailure != nil { list.append(relaunchButton) }
        if animation.state == .stopped { list.append(replayButton) }
        return list
    }

    var headline: String {
        switch state {
        case nil: "Screen Recording"
        case .granted: "Screen Recording is on"
        default: isUpdate ? "snapit needs Screen Recording turned back on" : "Turn on Screen Recording for snapit"
        }
    }

    var message: String {
        guard let state else { return "Checking Screen Recording…" }
        if state == .granted { return "snapit can take Captures." }
        if let failure = resetFailure {
            return "snapit could not clear its old Screen Recording entry (\(failure)). Open System Settings, select snapit in the Screen Recording list, press − to remove it, then choose Relaunch snapit."
        }
        let update = isUpdate ? "Each update needs Screen Recording again. snapit cleared its old entry and asked macOS afresh. " : ""
        switch variant {
        case .prompt:
            return update
                + (isUpdate ? "" : "snapit needs Screen Recording to take Captures. ")
                + "In macOS's message choose Open System Settings, then turn snapit on. macOS then offers Quit & Reopen: choose it."
        case .systemSettings:
            return update
                + (isUpdate ? "" : "macOS will not ask again. ")
                + "Open System Settings, turn snapit on in the Screen Recording list, then choose Quit & Reopen. If you chose Later, use Relaunch snapit."
        }
    }

    /// What the scripted run reads of the guide.
    func facts() -> [String] {
        var lines = [
            "guide-state=\(state?.rawValue ?? "unknown")",
            "guide-variant=\(variant.rawValue)",
            "guide-update=\(isUpdate ? "yes" : "no")",
            "guide-checks=\(checks)",
            "guide-animation=\(animation.state.rawValue)",
            "guide-loops=\(GuideAnimation.loops)",
            "guide-loop-seconds=\(Int(GuideAnimation.loopSeconds))",
            "guide-plays=\(animation.plays)",
            "guide-headline=\(headline)",
            "guide-message=\(message)",
            "guide-reset-failure=\(resetFailure ?? "none")",
            "guide-relaunch-error=\(relaunchError ?? "none")",
        ]
        lines += buttons.map { "button \($0.id)|\($0.title)|\($0.tooltip)" }
        return lines
    }

    // MARK: Animation

    /// The animation plays while the guide is on screen and the permission is still missing, and is
    /// cancelled the moment it is not.
    private func updateAnimation() {
        let wanted = isShown && isVisible && state != nil && state != .granted
        if wanted {
            if animation.state == .idle { animation.play() }
        } else {
            animation.stop()
        }
    }
}
